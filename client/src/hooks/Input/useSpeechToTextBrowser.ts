// FINAL, CORRECTED VERSION

import { useEffect, useMemo } from 'react';
import { useRecoilState } from 'recoil';
import SpeechRecognition, { useSpeechRecognition } from 'react-speech-recognition';
import useGetAudioSettings from './useGetAudioSettings';
import { useToastContext } from '~/Providers';
import store from '~/store';

const useSpeechToTextBrowser = (
  setText: (text: string) => void,
  // The `onTranscriptionComplete` parameter is no longer used here,
  // but we keep it to match the function signature.
  onTranscriptionComplete: (text: string) => void,
) => {
  const { showToast } = useToastContext();
  const { speechToTextEndpoint } = useGetAudioSettings();
  const isBrowserSTTEnabled = speechToTextEndpoint === 'browser';
  const [languageSTT] = useRecoilState<string>(store.languageSTT);

  const {
    listening,
    transcript,
    resetTranscript,
    isMicrophoneAvailable,
    browserSupportsSpeechRecognition,
  } = useSpeechRecognition();

  const isListening = useMemo(() => listening, [listening]);

  // This effect updates the visual text in the textarea
  useEffect(() => {
    setText(transcript);
  }, [transcript, setText]);

  const toggleListening = () => {
    if (!browserSupportsSpeechRecognition) {
      showToast({
        message: 'Browser does not support SpeechRecognition',
        status: 'error',
      });
      return;
    }

    if (!isMicrophoneAvailable) {
      showToast({
        message: 'Microphone is not available',
        status: 'error',
      });
      return;
    }

    if (isListening === true) {
      // === STOPPING LOGIC ===
      // THE KEY CHANGE: We only stop listening. We DO NOT submit or reset.
      // The transcribed text will remain in the input field for the user.
      SpeechRecognition.stopListening();
    } else {
      // === STARTING LOGIC ===
      // Clear any previous text and start listening
      resetTranscript();
      SpeechRecognition.startListening({
        language: languageSTT,
        continuous: true, // Always on, as you wanted
      });
    }
  };

  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.shiftKey && e.altKey && e.code === 'KeyL' && !isBrowserSTTEnabled) {
        toggleListening();
      }
    };

    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [isBrowserSTTEnabled, toggleListening]);

  return {
    isListening,
    isLoading: false,
    startRecording: toggleListening,
    stopRecording: toggleListening,
  };
};

export default useSpeechToTextBrowser;