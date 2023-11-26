//
//  AudioTranscriber.h
//  whisper.objc
//
//  Created by Anmol Jain on 11/25/23.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioQueue.h>

#define NUM_BUFFERS 3
#define MAX_AUDIO_SEC 30
#define SAMPLE_RATE 16000

struct whisper_context;

typedef struct
{
    int ggwaveId;
    bool isCapturing;
    bool isTranscribing;
    bool isRealtime;

    AudioQueueRef queue;
    AudioStreamBasicDescription dataFormat;
    AudioQueueBufferRef buffers[NUM_BUFFERS];

    int n_samples;
    int16_t * audioBufferI16;
    float   * audioBufferF32;

    struct whisper_context * ctx;

    void * vc;
} StateIn;

@interface AudioTranscriber : NSObject

- (void)toggleRecordingWithCompletion:(void (^)(NSString *transcribedText))completion;
- (void)startRecording;
- (void)stopRecording;
- (void)getTranscribedTextWithCompletion:(void (^)(NSString *transcribedText))completion;

@end
