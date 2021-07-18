
function with_midi(f::Function; port::Int, driver_class)
    driver = driver_class()
    try
        println("Opening port $port")
        driver.open_port(port)
        f(driver)
    catch e
        println(e)
    finally
        println("Closing port $port")
        driver.close_port()
    end
end

function transmit_midi_input_to(observable)
    function(midi_in)
        while true
            msg = midi_in.get_message()
            if (msg != nothing)
                ((signal, pitch, velocity), delta_time) = msg
                if signal == SUSTAIN_ON_SIGNAL
                    break
                end
                if signal == NOTE_ON_SIGNAL || signal == NOTE_OFF_SIGNAL
                    R.next!(observable, msg)
                end
            else
                sleep(0.001)
            end
        end
        R.complete!(observable)
    end
end