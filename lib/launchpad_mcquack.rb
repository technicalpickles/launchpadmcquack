# frozen_string_literal: true

require "matrix"
require "topaz"

class Launchpad
  autoload :BooleanState, "launchpad_mcquack/boolean_state"
  autoload :SonicPiBackend, "launchpad_mcquack/backends"
  autoload :UniMIDIBackend, "launchpad_mcquack/backends"

  POSITION_ENABLED_COLOR = 60
  BEAT_COLOR = 40
  COLOR_OFF = 0

  # see Launchpad X - Programmer's Reference
  # https://customer.novationmusic.com/en/support/downloads
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

  attr_accessor :state

  def initialize(backend:, output:)
    @backend = backend
    @state = BooleanState.new
    @output = output
  end

  def self.note_to_index(note)
    return @notes_to_index[note] if defined?(@notes_to_index)
    @notes_to_index = {}
    @@notes.each_with_index do |note, x, y|
      @notes_to_index[note] = [x, y]
    end

    @notes_to_index[note]
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
    when 0, 1, 2 then color_mode
    else
      raise ArgumentError, "unsupport color mode #{color_mode}"
    end
  end

  def light_position(color_mode, color, (x, y))
    note = @@notes[x, y]
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
    x, y = self.class.note_to_index(message.note)

    previous_state = @state[x, y]
    new_state = !previous_state
    if new_state
      light_position(:static, POSITION_ENABLED_COLOR, [x, y])
    else
      light_position(:static, COLOR_OFF, [x, y])
    end
    @state[x, y] = new_state

    # puts "#{index}: #{new_state}"
  end

  def run!(argv = [])
    bpm = 160
    period_in_seconds = 60 / bpm.to_f

    puts "#{bpm} bpm, #{period_in_seconds} interval"
    EventMachine.run do
      trap("SIGINT") do
        EventMachine.stop_event_loop
        off
      end

      @clock = Topaz::Clock.new(bpm) {
        tick
      }

      EventMachine.defer { @clock.start }

      @note_timer = EventMachine.add_periodic_timer(0.02) {
        handle_presses
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