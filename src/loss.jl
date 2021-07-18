using Zygote

LEARNING_RATE = 0.5

miditofreq(n) = 440 * 2^((n-69)/12)

overtones(f, n = 4) = map((x) -> (f * x, 1 / x), 1:n)

function loudness(amp)
    p_ref = 20 * 10^-6 # FIXME
    p_e = amp / sqrt(2)
    spl = 20 * log10(p_e / p_ref)
    (1/16) * 2^(spl/10)
end

# https://sethares.engr.wisc.edu/comprog.html
function dissonance(freq1, freq2, amp1, amp2)
    b_1 = 3.6
    b_2 = 5.75
    d_max = 0.24
    s_1 = 0.0207
    s_2 = 18.96

    l12 = min(loudness(amp1), loudness(amp2))

    f_1, f_2 = freq1 < freq2 ? [freq1, freq2] : [freq2, freq1]
    s = d_max / (s_1 * f_1 + s_2)
    x = s * (f_2 - f_1)
    l12 * (exp(-b_1 * x) - exp(-b_2 * x))
end

function total_dissonance(freq1, freq2)
    overtones1 = overtones(freq1)
    overtones2 = overtones(freq2)
    s = 0
    for (f1, a1) in overtones1
        for (f2, a2) in overtones2
            s += dissonance(f1, f2, a1, a1)
        end
    end
    s
end

function adjust(pitches)
    notes, bends = map(collect, zip(pitches...))
    freqs = miditofreq.(notes)
    function loss(xs)
        adjusted_freqs = freqs .* centtoratio.(bends + xs)
        sum(
            total_dissonance(f1, f2)
            for f1 in adjusted_freqs
            for f2 in adjusted_freqs
            if f1 != f2
        )
    end
    guess = -LEARNING_RATE * loss'(zero(bends))

    bends + guess
end