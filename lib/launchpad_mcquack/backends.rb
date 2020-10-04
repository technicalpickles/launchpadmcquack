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

  class SonicPiBackend
    def initialize(runtime)
      @runtime = runtime
      @launchpad_out = "launchpad_x_lpx_midi_in"
    end

    def puts(channel, velocity, note)
      @runtime.midi_note_on(note, velocity, channel: channel, port: @launchpad_out)
    end
  end
end
