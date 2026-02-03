import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'package:nock/core/constants/app_constants.dart';

/// Transcription Service - AI-powered Speech-to-Text
/// Converts voice messages to readable text using OpenAI Whisper API
class TranscriptionService {
  // Use centralized API key from AppConstants
  static const String _apiKey = AppConstants.openAiApiKey;
  static const String _whisperEndpoint = 'https://api.openai.com/v1/audio/transcriptions';

  /// Transcribe an audio file to text using OpenAI Whisper
  /// Returns the transcribed text or null if failed
  Future<String?> transcribeAudio(File audioFile) async {
    try {
      if (!await audioFile.exists()) {
        debugPrint('Audio file not found: ${audioFile.path}');
        return null;
      }

      // Whisper has a 25MB limit
      final fileSizeInMb = await audioFile.length() / (1024 * 1024);
      if (fileSizeInMb > 25) {
        debugPrint('Transcription failed: File too large (${fileSizeInMb.toStringAsFixed(2)}MB). Limit is 25MB.');
        return 'Audio too large (over 25MB) to transcribe.';
      }

      // Create multipart request
      final request = http.MultipartRequest('POST', Uri.parse(_whisperEndpoint));
      
      // Add authorization header
      request.headers['Authorization'] = 'Bearer $_apiKey';
      
      // Add the audio file (Whisper supports: mp3, mp4, mpeg, mpga, m4a, wav, webm)
      final String extension = audioFile.path.split('.').last.toLowerCase();
      request.files.add(await http.MultipartFile.fromPath(
        'file',
        audioFile.path,
        filename: 'vibe_media.$extension',
      ));
      
      // Specify the model
      request.fields['model'] = 'whisper-1';
      request.fields['language'] = 'en'; // Optional: auto-detect if removed
      request.fields['response_format'] = 'json';
      
      debugPrint('Sending transcription request...');
      
      // Send request
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      
      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(response.body);
        final transcribedText = jsonResponse['text'] as String?;
        debugPrint('Transcription successful: $transcribedText');
        return transcribedText;
      } else {
        debugPrint('Transcription failed: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('Transcription error: $e');
      return null;
    }
  }

  /// Transcribe a local audio/video file directly to OpenAI (Parallel Pipeline)
  /// This is an alias for transcribeAudio, used for the parallel fork pattern.
  Future<String?> transcribeFile(File audioFile) async {
    return await transcribeAudio(audioFile);
  }

  /// 🪝 3-Word Hook Generator - Creates intriguing teasers for widget engagement
  /// Uses GPT-4o-mini ($0.00015/1K tokens) to convert full transcription into
  /// a high-curiosity 3-word hook that drives app opens.
  /// 
  /// Example: "Hey, I saw your ex at the mall today..." → "Saw your ex..."
  Future<String?> generateWidgetHook(String transcription) async {
    if (transcription.isEmpty) return null;
    
    // For very short transcriptions (< 20 chars), just use them as-is
    if (transcription.length < 20) return transcription;
    
    try {
      final response = await http.post(
        Uri.parse('https://api.openai.com/v1/chat/completions'),
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': 'gpt-4o-mini',
          'messages': [
            {
              'role': 'system',
              'content': '''You are a hook generator for a social app widget. 
Create a 3-5 word intriguing teaser that makes the reader NEED to open the app.
Rules:
- Focus on emotion, secrets, urgency, or surprising elements
- Do NOT give away the ending or resolution
- End with "..." to create curiosity
- Keep it under 25 characters
- Use present tense when possible
Examples:
"I just saw your ex at the mall" → "Saw your ex..."
"I need to tell you something important" → "Need to tell you..."
"You won't believe what happened today" → "Won't believe this..."
"I'm thinking about breaking up with him" → "About to break up..."'''
            },
            {
              'role': 'user',
              'content': 'Create a hook for: "$transcription"'
            }
          ],
          'max_tokens': 30,
          'temperature': 0.7,
        }),
      );
      
      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(response.body);
        final hook = jsonResponse['choices'][0]['message']['content'] as String?;
        if (hook != null && hook.isNotEmpty) {
          // Clean up any quotes or extra formatting
          final cleanHook = hook.replaceAll('"', '').replaceAll("'", "").trim();
          debugPrint('🪝 Hook generated: $cleanHook');
          return cleanHook;
        }
      } else {
        debugPrint('Hook generation failed: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Hook generation error: $e');
    }
    
    // Fallback: Simple truncation with ellipsis
    return '${transcription.substring(0, transcription.length > 20 ? 20 : transcription.length)}...';
  }

  /// Transcribe from a URL (downloads first, then transcribes)
  Future<String?> transcribeFromUrl(String audioUrl) async {
    try {
      // Extract extension from URL to preserve format (m4a, mp4, etc.)
      String extension = 'm4a';
      try {
        final uri = Uri.parse(audioUrl);
        final path = uri.path;
        if (path.contains('.')) {
          extension = path.split('.').last.toLowerCase();
          // Cleanup Cloudinary parameters if any (e.g. .mp4?v=123)
          if (extension.contains('?')) {
            extension = extension.split('?').first;
          }
        }
      } catch (_) {}

      // Download to temp file with correct extension
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/temp_transcribe_${DateTime.now().millisecondsSinceEpoch}.$extension');
      
      final response = await http.get(Uri.parse(audioUrl));
      if (response.statusCode == 200) {
        await tempFile.writeAsBytes(response.bodyBytes);
        
        // Transcribe the downloaded file
        final result = await transcribeAudio(tempFile);
        
        // Clean up temp file safely
        try { if (await tempFile.exists()) await tempFile.delete(); } catch (_) {}
        
        return result;
      }
      return null;
    } catch (e) {
      debugPrint('Error transcribing from URL: $e');
      return null;
    }
  }
}

/// Transcription state for a single vibe
class TranscriptionState {
  final String? text;
  final bool isLoading;
  final String? error;

  const TranscriptionState({
    this.text,
    this.isLoading = false,
    this.error,
  });

  TranscriptionState copyWith({
    String? text,
    bool? isLoading,
    String? error,
  }) {
    return TranscriptionState(
      text: text ?? this.text,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
    );
  }
}

/// Transcription service provider
final transcriptionServiceProvider = Provider<TranscriptionService>((ref) {
  return TranscriptionService();
});

/// Transcription state notifier for managing transcription per vibe
class TranscriptionNotifier extends StateNotifier<Map<String, TranscriptionState>> {
  final TranscriptionService _service;

  TranscriptionNotifier(this._service) : super({});

  /// Get or load transcription for a vibe
  Future<void> loadTranscription(String vibeId, String audioUrl) async {
    // Check if already loaded
    if (state.containsKey(vibeId) && state[vibeId]?.text != null) {
      return;
    }

    // Set loading state
    state = {
      ...state,
      vibeId: const TranscriptionState(isLoading: true),
    };

    try {
      final text = await _service.transcribeFromUrl(audioUrl);
      state = {
        ...state,
        vibeId: TranscriptionState(text: text),
      };
    } catch (e) {
      state = {
        ...state,
        vibeId: TranscriptionState(error: e.toString()),
      };
    }
  }

  /// Get transcription for a vibe (returns null if not loaded)
  TranscriptionState? getTranscription(String vibeId) {
    return state[vibeId];
  }
}

/// Transcription state provider
final transcriptionStateProvider = 
    StateNotifierProvider<TranscriptionNotifier, Map<String, TranscriptionState>>((ref) {
  final service = ref.watch(transcriptionServiceProvider);
  return TranscriptionNotifier(service);
});
