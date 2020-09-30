# frozen_string_literal: true

require 'matrix'

class Launchpad
  class UniMIDIBackend
    def initialize
      # defer loading to this point
      require 'unimidi'
      require 'midi-message'
      
      # use second Novation Launchpad output, should be LPX MIDI output
      launchpad_devices = UniMIDI::Output.all.select do |output|
        output.name == "Focusrite - Novation Launchpad X"
      end

      unless @output = launchpad_devices.last
        raise ArgumentError, "no device connected"
      end
    end
    
    def message_for(channel, velocity, note)
      MIDIMessage.with(channel: channel, velocity: velocity) { note_on(note) }
    end
    
    def puts(channel, velocity, note)
      @output.puts message_for(channel, velocity, note).to_hex_s
    end
  end
  
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
    [ 81, 71, 61, 51, 41, 31, 21, 11 ],
    [ 82, 72, 62, 52, 42, 32, 22, 12 ],
    [ 83, 73, 63, 53, 43, 33, 23, 13 ],
    [ 84, 74, 64, 54, 44, 34, 24, 14 ],
    [ 85, 75, 65, 55, 45, 35, 25, 15 ],
    [ 86, 76, 66, 56, 46, 36, 26, 16 ],
    [ 87, 77, 67, 57, 47, 37, 27, 17 ],
    [ 88, 78, 68, 58, 48, 38, 28, 18 ]
  ]
  
  def initialize(backend:)
    @backend = backend
  end
  
  def self.setup(context = nil)
    if context && context.respond_to?(:midi_note_on)
      new(backend: SonicPiBackend.new(context))
    else
      new(backend: UniMIDIBackend.new)
    end
    
  end
  
  def color_mode_to_channel(color_mode)
    channel = case color_mode
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
    notes.each do |note|
      light_note(color_mode, color, note)
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
  
  def notes
    @@notes
  end
  
  def off
    light(:static, 0)
  end
  
  def light(mode, color)
    each_row do |i|
      light_row(mode, color, i)
    end
  end
  
  def each_row
    (0..(notes.row(0).size - 1 )).each do |i|
      yield i
    end
  end

  def self.run!(argv = [])
    require "pry"
    pry Launchpad.setup(self)
  end
end


@launchpad = Launchpad.setup(self)
@launchpad.off