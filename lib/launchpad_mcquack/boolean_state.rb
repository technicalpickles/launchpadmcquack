class Launchpad 
  class BooleanState
    include Enumerable

    def initialize
      @state = Matrix.zero(8)
      @state.each_with_index do |value, x, y|
        @state[x, y] = false
      end
    end

    def each(*args, &block)
      @state.each(*args, &block)
    end

    def each_with_index(*args, &block)
      @state.each_with_index(*args, &block)
    end

    def note_on?(note)
      index = Launchpad.note_to_index(note)
      @state[*index]
    end

    def [](x, y)
      @state[x, y]
    end

    def []=(x, y, value)
      @state[x, y] = value
    end

    def turn_on(x, y)
      @state[x, y] = 1
    end

    def turn_off(x, y)
      @state[x, y] = 1
    end

    def column_colors(column, color)
      @state.column(column).map { |state|
        if state
          color
        else
          0
        end
      }
    end
  end
end
