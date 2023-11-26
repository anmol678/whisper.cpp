//
//  AudioTranscriber.m
//  whisper.objc
//
//  Created by Anmol Jain on 11/25/23.
//

#import "AudioTranscriber.h"
#import "whisper.h"

#define NUM_BYTES_PER_BUFFER 16*1024

// callback used to process captured audio
void AudioInputCallback(void * inUserData,
                        AudioQueueRef inAQ,
                        AudioQueueBufferRef inBuffer,
                        const AudioTimeStamp * inStartTime,
                        UInt32 inNumberPacketDescriptions,
                        const AudioStreamPacketDescription * inPacketDescs);

@interface AudioTranscriber ()

@property (nonatomic, assign) StateIn stateInp;

@end

@implementation AudioTranscriber

- (instancetype)init {
    self = [super init];
    if (self) {
        // load the model
        {
            NSString *modelPath = [[NSBundle mainBundle] pathForResource:@"ggml-base.en" ofType:@"bin"];
            
            // check if the model exists
            if ([[NSFileManager defaultManager] fileExistsAtPath:modelPath]) {
                NSLog(@"Loading model from %@", modelPath);
                
                // create ggml context
                
                struct whisper_context_params cparams = whisper_context_default_params();
                
                _stateInp.ctx = whisper_init_from_file_with_params([modelPath UTF8String], cparams);
            }
            
            // check if the model was loaded successfully
            if (_stateInp.ctx != NULL) {
                // error
            }
        }
        
        // initialize audio format and buffers
        {
            [self setupAudioFormat:&_stateInp.dataFormat];
            
            _stateInp.n_samples = 0;
            _stateInp.audioBufferI16 = malloc(MAX_AUDIO_SEC*SAMPLE_RATE*sizeof(int16_t));
            _stateInp.audioBufferF32 = malloc(MAX_AUDIO_SEC*SAMPLE_RATE*sizeof(float));
            
            _stateInp.isTranscribing = false;
            _stateInp.isRealtime = false;
        }
    }
    
    return self;
}

- (void)toggleRecordingWithCompletion:(void (^)(NSString *))completion {
    if (_stateInp.isCapturing) {
        [self stopRecording];
        [self getTranscribedTextWithCompletion:^(NSString *transcribedText) {
            if (completion) {
                completion(transcribedText);
            }
        }];
    } else {
        [self startRecording];
        if (completion) {
            completion(@"");
        }
    }
}

- (void)startRecording {
    _stateInp.n_samples = 0;
    _stateInp.vc = (__bridge void *)(self);
    
    OSStatus status = AudioQueueNewInput(&_stateInp.dataFormat,
                                         AudioInputCallback,
                                         &_stateInp,
                                         CFRunLoopGetCurrent(),
                                         kCFRunLoopCommonModes,
                                         0,
                                         &_stateInp.queue);
    
    if (status == 0) {
        for (int i = 0; i < NUM_BUFFERS; i++) {
            AudioQueueAllocateBuffer(_stateInp.queue, NUM_BYTES_PER_BUFFER, &_stateInp.buffers[i]);
            AudioQueueEnqueueBuffer (_stateInp.queue, _stateInp.buffers[i], 0, NULL);
        }
        
        _stateInp.isCapturing = true;
        status = AudioQueueStart(_stateInp.queue, NULL);
        if (status == 0) {
            // Capturing - update UI to stop capturing
        }
    }
    
    if (status != 0) {
        [self stopRecording];
    }
}

- (void)stopRecording {
    
    // update UI to start capturing
    
    _stateInp.isCapturing = false;
    
    AudioQueueStop(_stateInp.queue, true);
    for (int i = 0; i < NUM_BUFFERS; i++) {
        AudioQueueFreeBuffer(_stateInp.queue, _stateInp.buffers[i]);
    }
    
    AudioQueueDispose(_stateInp.queue, true);
}

- (void)getTranscribedTextWithCompletion:(void (^)(NSString *))completion {
    if (_stateInp.isTranscribing) {
        if (completion) {
            completion(@"");
        }
        return;
    }
    
    NSLog(@"Processing %d samples", _stateInp.n_samples);
    
    _stateInp.isTranscribing = true;
    
    // dispatch the model to a background thread
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // process captured audio
        // convert I16 to F32
        for (int i = 0; i < self->_stateInp.n_samples; i++) {
            self->_stateInp.audioBufferF32[i] = (float)self->_stateInp.audioBufferI16[i] / 32768.0f;
        }
        
        // run the model
        struct whisper_full_params params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
        
        // get maximum number of threads on this device (max 8)
        const int max_threads = MIN(8, (int)[[NSProcessInfo processInfo] processorCount]);
        
        params.print_realtime   = true;
        params.print_progress   = false;
        params.print_timestamps = true;
        params.print_special    = false;
        params.translate        = false;
        params.language         = "en";
        params.n_threads        = max_threads;
        params.offset_ms        = 0;
        params.no_context       = true;
        params.single_segment   = self->_stateInp.isRealtime;
        
        CFTimeInterval startTime = CACurrentMediaTime();
        
        whisper_reset_timings(self->_stateInp.ctx);
        
        if (whisper_full(self->_stateInp.ctx, params, self->_stateInp.audioBufferF32, self->_stateInp.n_samples) != 0) {
            // Failed to run model
            if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(@"");
                });
            }
            return;
        }
        
        whisper_print_timings(self->_stateInp.ctx);
        
        CFTimeInterval endTime = CACurrentMediaTime();
        
        NSLog(@"\nProcessing time: %5.3f, on %d threads", endTime - startTime, params.n_threads);
        
        // result text
        __block NSString *result = @"";
        
        int n_segments = whisper_full_n_segments(self->_stateInp.ctx);
        for (int i = 0; i < n_segments; i++) {
            const char * text_cur = whisper_full_get_segment_text(self->_stateInp.ctx, i);
            
            // append the text to the result
            result = [result stringByAppendingString:[NSString stringWithUTF8String:text_cur]];
        }
        
        const float tRecording = (float)self->_stateInp.n_samples / (float)self->_stateInp.dataFormat.mSampleRate;
        
        // append processing time
        result = [result stringByAppendingString:[NSString stringWithFormat:@"\n\n[recording time:  %5.3f s]", tRecording]];
        result = [result stringByAppendingString:[NSString stringWithFormat:@"  \n[processing time: %5.3f s]", endTime - startTime]];
        
        // dispatch the result to the main thread
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_stateInp.isTranscribing = false;
            if (completion) {
                completion(result);
            }
        });
    });
}

- (void)setupAudioFormat:(AudioStreamBasicDescription*)format {
    format->mSampleRate       = WHISPER_SAMPLE_RATE;
    format->mFormatID         = kAudioFormatLinearPCM;
    format->mFramesPerPacket  = 1;
    format->mChannelsPerFrame = 1;
    format->mBytesPerFrame    = 2;
    format->mBytesPerPacket   = 2;
    format->mBitsPerChannel   = 16;
    format->mReserved         = 0;
    format->mFormatFlags      = kLinearPCMFormatFlagIsSignedInteger;
}

@end
