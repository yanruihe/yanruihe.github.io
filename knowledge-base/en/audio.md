# Linux Audio Drivers: ALSA, ASoC, and CODECs

This guide starts from practical symptoms—silence, distortion, and pops—and builds a repeatable debugging path. An embedded sound card is more than a CODEC driver that probes successfully: the CPU DAI, CODEC DAI, machine connections, clocks, DMA, DAPM route, analog rails, and userspace parameters must all line up.

## 1. Playback path and ASoC components

```text
Application/aplay → ALSA PCM → DMA/platform → CPU DAI (I2S/PCM) ⇄ CODEC DAI → DAC/analog output/amp
                                         Machine driver describes board links, clocks, and controls
```

- **ALSA PCM**: handles sample format, rate, channels, period/buffer, and playback/capture streams.
- **CPU DAI**: configures the SoC-side I2S/PCM interface, clocks, and data format.
- **CODEC DAI/driver**: controls the CODEC digital interface, registers, DAC/ADC, mixer, and DAPM description.
- **Machine driver**: binds the SoC, CODEC, and board-specific amp/jack detection into a sound card and describes clock/board policy.
- **DMA/platform**: moves PCM data; period IRQ, FIFO watermark, or bus-bandwidth faults can cause underruns/overruns.

ASoC DAPM powers audio components according to active streams and routes. Missing mixer controls, a disconnected route, or an unpowered widget can leave a card that appears operational but has no sound at its endpoint.

## 2. First bring-up: enumeration to audible output

```sh
dmesg | grep -Ei 'asoc|alsa|snd|codec|i2s|dma'
cat /proc/asound/cards
aplay -l
arecord -l
amixer -c 0 contents
```

Check kernel configuration; sound-card/link device-tree phandles; I2S controller and CODEC address, power, and reset; DAI format; clock-master relationship; and supported rate constraints. Then verify board wiring: speaker-amp enable, jack detection, analog rails, microphone bias, and mute GPIO.

Use `speaker-test` or `aplay` with a known PCM/WAV file. Select the card and controls first, so an unsupported test-file format is not mistaken for a driver bug:

```sh
aplay -D hw:0,0 -f S16_LE -r 48000 -c 2 test.wav
arecord -D hw:0,0 -f S16_LE -r 48000 -c 2 -d 5 capture.wav
```

Confirm the formats supported by the actual hardware. These example parameters are common test values, not a claim that every board supports 48 kHz, 16-bit stereo.

## 3. Localize silence, distortion, and XRUNs

| Symptom | First checks |
| --- | --- |
| No sound card/PCM | Driver probe, device-tree phandles, I2C/SPI CODEC enumeration, deferred probes, kernel config |
| PCM starts but is silent | `amixer` mute/volume, DAPM route, amp enable, analog rails, DAC route, headphone/speaker selection |
| Noise, wrong pitch, or distortion | MCLK/BCLK/LRCLK, clock master, polarity/slot/width, sample format, channel mapping, ground/analog supply |
| `underrun` / `overrun` | DMA setup and addresses, period/buffer, IRQ latency, CPU load, bus bandwidth, route format |
| Capture is all zero | Mic bias, input mux, ADC power, gain, clocks, physical input, and `arecord` parameters |

Use a scope to inspect MCLK, BCLK, LRCLK, and serial data. For protocol decoding, choose a logic-analyzer sample rate and width that can resolve the bus. Correlate control values and waveforms with recorded samples and listening tests instead of guessing registers by ear.

## 4. POP/CLICK and audio-quality tuning

Pops often come from poor sequencing between rails/bias/analog output and digital mute, not simply “volume too high.” Verify each stage: mute before playback → power rails and stabilize clocks → configure CODEC and routes → wait for bias as specified by the chip → enable DAC/amp and gradually unmute. On stop, mute first, then disable amp and power in the required order. Exact delays and discharge paths must follow the CODEC/amp data sheet. ASoC provides DAPM and pop/click mechanisms, but the board circuitry and driver implementation still determine the result.

For audio quality, fix the device, source, output load, and measurement conditions before tuning digital/analog gain, filters, EQ, sample format, or dynamics. Keep original recordings and compare frequency response, noise floor, THD+N, clipping, and latency; subjective listening should not be the only acceptance criterion.

## 5. Echo cancellation: confirm the system architecture first

AEC (Acoustic Echo Cancellation) needs both the near-end microphone signal and a playback reference, with stable timestamps, sample rate, full-duplex routing, and a latency model. It is often implemented in DSP, an audio HAL, or a userspace processing chain—not as a universal CODEC switch. Record alignment between the playback reference and microphone capture, device/acoustic path latency, double-talk behavior, tail length, and residual echo. First prove that the reference reaches AEC and capture actually passes through it; only then tune algorithm parameters or acoustics.

## 6. Verification checklist

For every change, record kernel/device tree, CODEC and amp revisions, control state, DAI format/clocks, PCM parameters, waveforms, sample recordings, and test load. Cover cold boot, rapid start/stop, headphone insertion, volume changes, suspend/resume, concurrent playback/capture, and system load. Test functionality, pops, noise, distortion, and latency separately.

## Official references

- [ALSA SoC Layer Overview](https://docs.kernel.org/sound/soc/overview.html)
- [ALSA SoC documentation index](https://docs.kernel.org/sound/soc/index.html)
- [ALSA PCM API](https://docs.kernel.org/sound/kernel-api/alsa-driver-api.html)
