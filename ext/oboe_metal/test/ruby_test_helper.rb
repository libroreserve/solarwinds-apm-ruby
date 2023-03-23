class TestMe
  class Snapshot
    class << self
      # !!! do not shift the definition of take_snapshot from line 7 !!!
      # the line number is used to verify a test in frames_test.cc
      def take_snapshot
        # puts "getting frames ...."
        begin
          ::RubyCalls.get_frames   # RubyCalls is defined in frames_test.cc
        rescue StandardError => e
          puts "oops, getting frames didn't work"
          puts e
        end
      end

      def all_kinds
        begin
          Teddy.new.sing do
            take_snapshot
          end
        rescue StandardError => e
          puts "Ruby call did not work"
          puts e
        end
      end
    end
  end

  # example call 
  # sing do
  #   puts 'a'
  # end
  class Teddy
    attr_accessor :name

    def sing
      3.times do
        yodel do
          html_wrap("title", "Hello") { |_html| yield }
        end
      end
    end

    private

    def yodel
      a_proc = -> (x) { result = x * x;  yield }
      in_block(&a_proc)
    end

    def in_block(*)
      begin
        yield 7
        # puts "block called!"
      rescue StandardError => e
        puts "no, this should never happen"
        puts e
      end
    end

    def html_wrap(tag, text)
      html = "<#{tag}>#{text}</#{tag}>"
      yield html
    end
  end
end
