#!/usr/bin/env python3
"""동물의숲 스타일 대화 효과음 생성"""

import math
import struct
import wave

def generate_beep_sound(frequency=900, duration=0.08, sample_rate=44100, amplitude=0.8):
    """
    단순 비프음 생성 (동물의숲 스타일)

    Args:
        frequency: 주파수 (Hz)
        duration: 지속시간 (초)
        sample_rate: 샘플링 레이트 (Hz)
        amplitude: 진폭 (0.0-1.0)

    Returns:
        WAV 파일 데이터 (바이트)
    """
    num_samples = int(sample_rate * duration)
    samples = []

    # 사인파 생성
    for i in range(num_samples):
        t = i / sample_rate
        # 진폭 감쇠 (부드러운 끝)
        envelope = 1.0 - (i / num_samples) * 0.4
        sample = int(32767 * amplitude * envelope * math.sin(2 * math.pi * frequency * t))
        samples.append(sample)

    return samples

def write_wav_file(filename, samples, sample_rate=44100):
    """WAV 파일 작성"""
    with wave.open(filename, 'w') as wav_file:
        wav_file.setnchannels(1)  # 모노
        wav_file.setsampwidth(2)  # 16비트
        wav_file.setframerate(sample_rate)

        # 샘플을 바이트로 변환
        for sample in samples:
            # 클리핑 처리
            sample = max(-32768, min(32767, sample))
            wav_file.writeframes(struct.pack('<h', sample))

if __name__ == '__main__':
    import os

    output_dir = os.path.join(
        os.path.dirname(__file__),
        '../assets/sounds/ui'
    )
    os.makedirs(output_dir, exist_ok=True)

    # 동물의숲 스타일 톤 (높은 주파수, 강한 진폭)
    samples = generate_beep_sound(frequency=900, duration=0.08, amplitude=0.8)
    output_file = os.path.join(output_dir, 'dialogue_text_reveal.wav')
    write_wav_file(output_file, samples)

    print(f"✓ 효과음 생성: {output_file}")
    print(f"  주파수: 900Hz, 진폭: 0.8, 지속시간: 0.08s")
