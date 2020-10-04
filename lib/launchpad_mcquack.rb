# frozen_string_literal: true

require "matrix"

class Launchpad
  class UniMIDIBackend
    def initialize
      # defer loading to this point
      require "unimidi"
      require "midi-message"

      # use second Novation Launchpad output, should be LPX MIDI output
      launchpad_outputs = UniMIDI::Output.all.select { |output|
        output.name == "Focusrite - Novation Launchpad X"
      }

      # use second Novation Launchpad input, should be LPX MIDI input
      launchpad_inputs = UniMIDI::Input.all.select { |output|
        output.name == "Focusrite - Novation Launchpad X"
      }

      @output = launchpad_outputs.last
      @input = launchpad_inputs.last
      return if @output && @input

      raise ArgumentError, "no device connected"
    end

    def message_for(channel, velocity, note)
      MIDIMessage.with(channel: channel, velocity: velocity) { note_on(note) }
    end

    def puts(channel, velocity, note)
      @output.puts message_for(channel, velocity, note).to_hex_s
    end

    def gets
      @input.gets.reject { |event|
        # don't try to handle things longer than 4 bytes, which is all midi message handles
        event[:data].size > 4
      }.map { |event|
        MIDIMessage.parse event[:data]
      }.select { |message|
        message.is_a?(MIDIMessage::NoteOn)
      }.reject { |message|
        # release triggers as velocity 0 for some reason
        message.velocity == 0
      }
    end
  end

  POSITION_ENABLED_COLOR = 60
  BEAT_COLOR = 40
  COLOR_OFF = 0

  class SonicPiBackend
    def initialize(runtime)
      @runtime = runtime
      @launchpad_out = "launchpad_x_lpx_midi_in"
    end

    def puts(channel, velocity, note)
      @runtime.midi_note_on(note, velocity, channel: channel, port: @launchpad_out)
    end
  end

  @@notes = Matrix[
    [81, 71, 61, 51, 41, 31, 21, 11],
    [82, 72, 62, 52, 42, 32, 22, 12],
    [83, 73, 63, 53, 43, 33, 23, 13],
    [84, 74, 64, 54, 44, 34, 24, 14],
    [85, 75, 65, 55, 45, 35, 25, 15],
    [86, 76, 66, 56, 46, 36, 26, 16],
    [87, 77, 67, 57, 47, 37, 27, 17],
    [88, 78, 68, 58, 48, 38, 28, 18]
  ]

  def self.note_to_index(note)
    return @notes_to_index[note] if defined?(@notes_to_index)
    @notes_to_index = {}
    @@notes.each_with_index do |note, x, y|
      @notes_to_index[note] = [x, y]
    end

    @notes_to_index[note]
  end

  attr_accessor :state
  def initialize(backend:, output:)
    @backend = backend
    @state = BooleanState.new
    @output = output
  end

  def self.setup(context: nil, output: nil)
    if context&.respond_to?(:midi_note_on)
      new(backend: SonicPiBackend.new(context))
    else
      new(backend: UniMIDIBackend.new, output: output)
    end
  end

  def color_mode_to_channel(color_mode)
    case color_mode
    # Channel 1, Notes: 90h (144), Control Changes: B0h (176): Static colour.
    # Channel 2, Notes: 91h (145), Control Changes: B1h (177): Flashing colour.
    # Channel 3, Notes: 92h (146), Control Changes: B2h (178): Pulsing colour.
    # NOTE midi channel 1 ends up being 0 here
    when :static then 0
    when :flashing then 1
    when :pulsing then 2
    else
      raise ArgumentError, "unsupport color mode #{color_mode}"
    end
  end

  def light_position(color_mode, color, position)
    note = @@notes[*position]
    light_note(color_mode, color, note)
  end

  def light_note(color_mode, color, note)
    @backend.puts color_mode_to_channel(color_mode), color, note
  end

  def light_notes(color_mode, color, notes)
    if color.is_a?(Array) || color.is_a?(Vector)
      raise "mismatch size #{color} vs #{notes}" unless notes.size == color.size
    end

    notes.each_with_index do |note, i|
      local_color = if color.is_a?(Array) || color.is_a?(Vector)
        color[i]
      else
        color
      end

      # puts "#{note}: #{color_mode} #{local_color}"
      light_note(color_mode, local_color, note)
    end
  end

  def light_column(color_mode, color, row)
    notes = @@notes.row(row)
    light_notes(color_mode, color, notes)
  end

  def light_row(color_mode, color, column)
    notes = @@notes.column(column)
    light_notes(color_mode, color, notes)
  end

  def play_row(column)
    @@notes.column(column).each_with_index do |note, i|
      if @state.note_on?(note)
        # TODO different channels?
        @output.puts MIDIMessage.with(channel: i, velocity: 100) { note_on(note) }
      end
    end
  end

  def light_row_to_state(color_mode, color, column)
    notes = @@notes.column(column)
    colors = @state.column_colors(column, color)

    light_notes(color_mode, colors, notes)
  end

  def notes
    @@notes
  end

  def off
    light(:static, COLOR_OFF)
  end

  def light(mode, color)
    each_row do |i|
      light_row(mode, color, i)
    end
  end

  def each_row
    (0..(notes.row(0).size - 1)).each do |i|
      yield i
    end
  end

  def gets
    @backend.gets
  end

  def handle_presses
    gets.each do |message|
      handle_press(message)
    end
  end

  def handle_press(message)
    index = self.class.note_to_index(message.note)

    previous_state = @state[*index]
    new_state = !previous_state
    if new_state
      light_position(:static, POSITION_ENABLED_COLOR, index)
    else
      light_position(:static, COLOR_OFF, index)
    end
    @state[*index] = new_state

    # puts "#{index}: #{new_state}"
  end

  def self.run!(_argv = [])
    require "pry"
    pry Launchpad.setup(self)
  end

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

  def tick
    thread = Thread.current
    unless thread.key?(:counter)
      thread[:counter] = 0
    end

    beat = thread[:counter] % 8
    EventMachine.defer do
      play_row(beat)
    end

    previous_beat = beat - 1 # this will correctly work when it's negative, thanks ruby!

    EventMachine.defer do
      light_row_to_state(:static, POSITION_ENABLED_COLOR, previous_beat)
    end

    EventMachine.defer do
      light_row(:static, BEAT_COLOR, beat)
    end

    thread[:counter] = thread[:counter] + 1
  end
end

# @launchpad = Launchpad.setup(self)
# @launchpad.off

# @launchpad.state.each_with_index do |state, x, y|
#   @launchpad.state[x, y] = rand(2)
# end

# @launchpad.state.each_with_index do |state, x, y|
#   puts "x=#{x}, y=#{y}"
#   if state == 1
#     @launchpad.light_position(:static, 20, [x, y])
#   else
#     @launchpad.light_position(:static, 0, [x, y])
#   end
# end
