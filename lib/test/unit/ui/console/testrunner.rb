#--
#
# Author:: Nathaniel Talbott.
# Copyright:: Copyright (c) 2000-2003 Nathaniel Talbott. All rights reserved.
# License:: Ruby license.

require 'test/unit/ui/testrunnermediator'
require 'test/unit/ui/testrunnerutilities'

module Test
  module Unit
    module UI
      module Console

        # Runs a Test::Unit::TestSuite on the console.
        class TestRunner
          extend TestRunnerUtilities

          # Creates a new TestRunner for running the passed
          # suite. If quiet_mode is true, the output while
          # running is limited to progress dots, errors and
          # failures, and the final result. io specifies
          # where runner output should go to; defaults to
          # STDOUT.
          def initialize(suite, output_level=NORMAL, io=STDOUT)
            if (suite.respond_to?(:suite))
              @suite = suite.suite
            else
              @suite = suite
            end
            @output_level = output_level
            @io = io
            # Invoca Patch
            @test_index = 0
            @term_width = (`stty size`.split.last.to_i rescue nil if @io.isatty) || 100
            @fault
            # End Invoca Patch
          end

          # Begins the test run.
          def start
            setup_mediator
            attach_to_mediator
            return start_mediator
          end

          private
          def setup_mediator
            @mediator = create_mediator(@suite)
            suite_name = @suite.to_s
            if ( @suite.kind_of?(Module) )
              suite_name = @suite.name
            end
            output("Loaded suite #{suite_name}")
          end
          
          def create_mediator(suite)
            return TestRunnerMediator.new(suite)
          end
          
          def attach_to_mediator
            @mediator.add_listener(TestResult::FAULT, &method(:add_fault))
            @mediator.add_listener(TestRunnerMediator::STARTED, &method(:started))
            @mediator.add_listener(TestRunnerMediator::FINISHED, &method(:finished))
            @mediator.add_listener(TestCase::STARTED, &method(:test_started))
            @mediator.add_listener(TestCase::FINISHED, &method(:test_finished))
          end
          
          def start_mediator
            return @mediator.run_suite
          end
          
          def add_fault(fault)
          # Invoca Patch
            @fault_count += 1
            output("\n-------\n", PROGRESS_ONLY)
            output(fault.long_display, PROGRESS_ONLY)
            output(@io.isatty ? "\n\n\n" : "\n", PROGRESS_ONLY)
            #output_single(fault.single_character_display, PROGRESS_ONLY)
            # End Invoca Patch
          end
          
          def started(result)
            @result = result
            output("Started")
          end
          
          def finished(elapsed_time)
          # Invoca Patch
            output("\r\x1b[0J") if @io.isatty
            output("Finished in #{elapsed_time.to_i} seconds.")
            nl
            output(@result)          
          end
          
          def self.exclusive_overwrite(read_filename, write_filename)
            contents = File.read(read_filename) rescue ''
            new_contents = yield(contents)

            File.open(write_filename, 'a') do |fwrite|
              begin
                fwrite.flock File::LOCK_EX
                write_contents =
                  if fwrite.tell > 0
                    new_contents[(new_contents.index("\n")+1)..-1]
                  else
                    new_contents
                  end
                fwrite.write(write_contents)
              ensure
                fwrite.flock File::LOCK_UN
              end
            end
          end

          def self.runtime_log
            Pathname.new(ENV['BUILD_REPORTS'] || '.') + '..' + 'rails_3_test_stats.yml'
          end

          def self.local_runtime_log
            Pathname.new(ENV['BUILD_REPORTS'] || '.') + 'rails_3_test_stats.yml'
          end

          def write_stats
            if ENV['BUILD_REPORTS'] # only write stats when BUILD_REPORTS is set
              self.class.exclusive_overwrite(self.class.runtime_log, self.class.local_runtime_log) do |contents|
                result = {}
                original = YAML.load(contents) || {}
                @stats.each do |stats_file_class, stats_file_hash|
                  result[stats_file_class] = original[stats_file_class] || {}
                  stats_file_hash.each do |stats_test_case, stats_values|
                    if stats_test_case.start_with?('_')
                      result[stats_file_class][stats_test_case] = stats_values
                    else
                      result_test_case_hash = (result[stats_file_class][stats_test_case] ||= {})
                      stats_values.each do |attribute, value|
                        if attribute == 'last_result'
                          if result_test_case_hash['last_result'] == value
                            result_test_case_hash['since'] ||= stats_values['last_run']
                          else
                            result_test_case_hash['since']   = stats_values['last_run'] # just changed from success to failure or vice versa
                          end
                        end
                        result_test_case_hash[attribute]   = value
                      end
                    end
                  end
                end
                result.to_yaml
              end
            end
          end

          private :write_stats

          def stats
            unless @stats
              @stats = {}
              at_exit { write_stats }
            end
            @stats
          end
          
          def test_started(name)
            output_single(name + ": ", VERBOSE)

            @total_size ||= ((@suite.size - 1).nonzero? || 1)
            #output_single(".", PROGRESS_ONLY) unless (@already_outputted)
            match = /^(?:test: )?(.*)(\([^)]+\))$/.match(name) or raise name
            @test_case, @test_file_class = match.captures
            @test_case.strip!
            @test_file_class = @test_file_class[1..-2]
            prefix = "%3d%% %4d of %d " % [@test_index*100/@total_size, @test_index - @total_size, @total_size]
            test_file_and_case = (@test_file_class + ' ' + @test_case)[0, @term_width - prefix.size]
            if @io.isatty
              output_single("\r\x1b[0J#{prefix}#{test_file_and_case}")
              nl(VERBOSE)
            end

            @start_time = Time.now
            @fault_count = 0
          end

          def test_finished(name)
            @test_index += 1
            seconds = Time.now - @start_time
            filename = self.class.infer_filename(@test_file_class)
            file_stats = (stats[filename] ||= {})
            file_stats['_class'] = @test_file_class
            file_stats['_seconds'] = file_stats['_seconds'].to_i + seconds
            case_stats = (file_stats[@test_case]  ||= {})
            case_stats['seconds'] = seconds
            case_stats['last_result'] = @fault_count == 0 ? 'success' : 'failure'
            case_stats['last_run'   ] = "#{@start_time.to_i} #{@start_time.rfc2822}"
          end

          def self.class_directory(suspect)
            "test/" +
                case suspect.superclass.name
                  when "ActionDispatch::IntegrationTest"
                    "integration/"
                  when "ActionDispatch::PerformanceTest"
                    "performance/"
                  when "ActionController::TestCase"
                    "functional/"
                  when "ActionView::TestCase"
                    "unit/helpers/"
                  else
                    "unit/"
                end
          end

          def self.class_to_filename(suspect)
            return suspect unless suspect =~ /^[A-Z]/i

            word = suspect.to_s.dup
            word.gsub!(/([A-Z])/) { |pat| '_' + pat.downcase }
            word.gsub!(/::/, '/')
            word.gsub!(/\A_/, '')
            word.gsub!(/\/_/, '/')
            word.tr!("-", "_")
            word
          end

          def self.infer_filename(class_name)
            klass = instance_eval(class_name)
            if klass.respond_to?(:test_filename)
              klass.test_filename
            else
              class_directory(klass) + class_to_filename(class_name) + ".rb"
            end
          end
          # End Invoca Patch

          def nl(level=NORMAL)
            output("", level)
          end
          
          def output(something, level=NORMAL)
            @io.puts(something) if (output?(level))
            @io.flush
          end
          
          def output_single(something, level=NORMAL)
            @io.write(something) if (output?(level))
            @io.flush
          end
          
          def output?(level)
            level <= @output_level
          end
        end
      end
    end
  end
end

if __FILE__ == $0
  Test::Unit::UI::Console::TestRunner.start_command_line_test
end
