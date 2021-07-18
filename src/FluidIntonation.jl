module FluidIntonation

import MIDI
import PyCall
import Match

import FunctionalCollections as FC
import Rocket as R

include("stream.jl")
include("loss.jl")
include("midi_io.jl")

TICK = 1

NOTE_ON_SIGNAL= 144
NOTE_OFF_SIGNAL= 128
SUSTAIN_ON_SIGNAL = 176

channel(pitch) = pitch % 12

centtoratio(cent) = 10^((log10(2) / 1200) * cent)
pitchbend(bend_ratio) = round.(8192 .+ 4096 * 12 * log2.(bend_ratio))

function possible_adjustments(event, state)
    new_state = Match.@match event begin
        MIDI.NoteOnEvent(_, _, note, _)  => haskey(state, note) ? state : FC.assoc(state, note, 0)
        MIDI.NoteOffEvent(_, _, note, _) => haskey(state, note) ? FC.dissoc(state, note) : state
        _                                => state
    end

    if (length(new_state) > 1)
        note_adjustment_pairs = [(a, b) for (a, b) in new_state]
        new_adjustments = adjust(note_adjustment_pairs)
        new_adjustment_pairs = collect(zip(map(first, note_adjustment_pairs), new_adjustments))
        bends = map(new_adjustment_pairs) do (note, adj)
            MIDI.PitchBendEvent(TICK, Int(round(pitchbend(centtoratio(adj)))), channel=channel(note))
        end
        return bends, FC.PersistentHashMap(new_adjustment_pairs)
    else
        return MIDI.MIDIEvent[], new_state
    end
end

function make_input_event(msg)
    (signal, pitch, velocity), _ = msg
    if signal == NOTE_ON_SIGNAL
        MIDI.NoteOnEvent(TICK, pitch, velocity, channel=channel(pitch))
    elseif signal == NOTE_OFF_SIGNAL
        MIDI.NoteOffEvent(TICK, pitch, velocity, channel=channel(pitch))
    else
        error("Could not recognize signal") 
    end
end

function make_output_event(evt)
    out = Match.@match evt begin
        MIDI.NoteOnEvent(_, status, note, velocity)  => [status, note, velocity]
        MIDI.NoteOffEvent(_, status, note, velocity) => [status, note, velocity]
        MIDI.PitchBendEvent(_, status, pitch)        => [status, midibits(UInt16(pitch))...]
        other                                        => error(other)
    end
    PyCall.PyVector(out)
end

function midibits(value::UInt16)
    # split into two 7 bit segments
    mask = UInt16((1 << 7) - 1)
    lsb = value & mask
    msb = (value & (mask << 7)) >> 7
    (lsb, msb)
end

source = R.Subject(Tuple{Vector{Int64}, Float64}, scheduler = R.AsyncScheduler())

input_stream = source |>
    R.map(MIDI.MIDIEvent, make_input_event) |>
    R.take_until(source |> filter(x -> typeof(x) == MIDI.ControlChangeEvent))

intervals = R.interval(100)

adjustment_stream = R.merged((input_stream, intervals)) |>
    stateful_flatmap(MIDI.MIDIEvent, possible_adjustments, FC.PersistentHashMap{Int, Float64}())

output_stream = R.merged((input_stream, adjustment_stream)) |>
    R.map(PyCall.PyVector, make_output_event)

function test()
    println("Starting test")
    R.subscribe!(output_stream, (msg) -> @show msg)
    R.next!(source, ([NOTE_ON_SIGNAL, 100, 100], 1.0))
    R.next!(source, ([NOTE_ON_SIGNAL, 120, 100], 1.0))
    R.next!(source, ([NOTE_ON_SIGNAL, 123, 80], 1.0))
    R.next!(source, ([NOTE_OFF_SIGNAL, 100, 100], 1.0))
    println("Done")
end

function start()
    rtmidi = PyCall.pyimport("rtmidi")
    with_midi(port=8, driver_class=rtmidi.MidiOut) do midi_out
        R.subscribe!(output_stream, (msg) -> midi_out.send_message(msg))

        with_midi(transmit_midi_input_to(source), port=0, driver_class=rtmidi.MidiIn)
    end
end

end # module
