# Invoca Patch
module Test
  module Unit
    class FixtureOrderedSuite < TestSuite
      attr_reader :name, :tests
  
      def initialize(suite)
        @name = suite.name
        @tests = []
        load_tests suite
        sort_tests
        #display
      end

      def load_tests suite
        suite.tests.each do |test|
          if test.is_a?(TestSuite)
            load_tests test
          else
            @tests << test
          end
        end
      end

      def sort_tests
        @tests.sort! do |x,y|
          ( x.fixture_realm.to_s <=> y.fixture_realm.to_s ).nonzero? ||
            ( x.class.name <=> y.class.name ).nonzero? ||
            ( x.method_name <=> y.method_name ).nonzero?
        end
      end

      def display
        @tests.each do |t|
          puts "  #{t.fixture} #{t.class.name} #{t.method_name}"
        end
      end
    end
  end
end
# End Invoca Patch
