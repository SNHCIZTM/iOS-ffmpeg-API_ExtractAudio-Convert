//
//  ViewController.m
//  AudioConverter
//
//  Created by gxy on 2020/2/29.
//  Copyright © 2020 Fabulous. All rights reserved.
//

#import "libavutil/log.h"
#import "libavformat/avformat.h"
#import "ViewController.h"

#define ERROR_STR_SIZE 1024
@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self extractAudio];
    [self remuxing];
}

-(void)extractAudio {
    int err_code;

    const char *src_filename = NULL;
    char *dst_filename = "/Users/gxy/Desktop/ios/audio.aac";
    NSString *fromFile = [[NSBundle mainBundle]pathForResource:@"video.mov" ofType:nil];
    src_filename = [fromFile UTF8String];

    FILE *dst_fd = NULL;

    int audio_stream_index = -1;

    AVFormatContext *ofmt_ctx = NULL;
    AVOutputFormat *output_fmt = NULL;

    AVStream *in_stream = NULL;
    AVStream *out_stream = NULL;

    AVFormatContext *fmt_ctx = NULL;
    AVPacket pkt;

    av_log_set_level(AV_LOG_DEBUG);

    if((err_code = avformat_open_input(&fmt_ctx, src_filename, NULL, NULL)) < 0){
        av_log(NULL, AV_LOG_DEBUG, "Could not open source file\n");
    }

    if((err_code = avformat_find_stream_info(fmt_ctx, NULL)) < 0) {
        av_log(NULL, AV_LOG_DEBUG, "failed to find stream information\n");
    }

    av_dump_format(fmt_ctx, 0, src_filename, 0);

    in_stream = fmt_ctx->streams[1];
    AVCodecParameters *in_codecpar = in_stream->codecpar;
    if(in_codecpar->codec_type != AVMEDIA_TYPE_AUDIO){
        av_log(NULL, AV_LOG_ERROR, "The Codec type is invalid!\n");
    }

    ofmt_ctx = avformat_alloc_context();
    output_fmt = av_guess_format(NULL, dst_filename, NULL);
    ofmt_ctx->oformat = output_fmt;
    out_stream = avformat_new_stream(ofmt_ctx, NULL);
    out_stream->codecpar->codec_tag = 0;

    if((err_code = avio_open(&ofmt_ctx->pb, dst_filename, AVIO_FLAG_WRITE)) < 0) {
        av_log(NULL, AV_LOG_DEBUG, "Could not open file\n");
    }

    av_dump_format(ofmt_ctx, 0, dst_filename, 1);

    av_init_packet(&pkt);
    pkt.data = NULL;
    pkt.size = 0;

    audio_stream_index = av_find_best_stream(fmt_ctx, AVMEDIA_TYPE_AUDIO, -1, -1, NULL, 0);
    if(audio_stream_index < 0){
        av_log(NULL, AV_LOG_DEBUG, "Could not find stream in input file\n");
    }

    if (avformat_write_header(ofmt_ctx, NULL) < 0) {
        av_log(NULL, AV_LOG_DEBUG, "Error occurred when opening output file\n");
    }

    while(av_read_frame(fmt_ctx, &pkt) >=0 ){
        if(pkt.stream_index == audio_stream_index){
            pkt.pts = av_rescale_q_rnd(pkt.pts, in_stream->time_base, out_stream->time_base, (AV_ROUND_NEAR_INF|AV_ROUND_PASS_MINMAX));
            pkt.dts = pkt.pts;
            pkt.duration = av_rescale_q(pkt.duration, in_stream->time_base, out_stream->time_base);
            pkt.pos = -1;
            pkt.stream_index = 0;
            av_interleaved_write_frame(ofmt_ctx, &pkt);
            av_packet_unref(&pkt);
        }
    }

    av_write_trailer(ofmt_ctx);

    avformat_close_input(&fmt_ctx);
    if(dst_fd) {
        fclose(dst_fd);
    }

    avio_close(ofmt_ctx->pb);
}

-(void)remuxing {
    AVOutputFormat *ofmt = NULL;
    AVFormatContext *ifmt_ctx = NULL, *ofmt_ctx = NULL;
    AVPacket pkt;
    const char *in_filename, *out_filename;
    int ret, i;
    int stream_index = 0;
    int *stream_mapping = NULL;
    int stream_mapping_size = 0;
    
    in_filename  = "/Users/gxy/Desktop/ios/audio.aac";
    out_filename = "/Users/gxy/Desktop/ios/audio.wav";

    if ((ret = avformat_open_input(&ifmt_ctx, in_filename, 0, 0)) < 0) {
        fprintf(stderr, "Could not open input file '%s'", in_filename);
        goto end;
    }

    if ((ret = avformat_find_stream_info(ifmt_ctx, 0)) < 0) {
        fprintf(stderr, "Failed to retrieve input stream information");
        goto end;
    }
    av_dump_format(ifmt_ctx, 0, in_filename, 0);

    avformat_alloc_output_context2(&ofmt_ctx, NULL, NULL, out_filename);
    if (!ofmt_ctx) {
        fprintf(stderr, "Could not create output context\n");
        ret = AVERROR_UNKNOWN;
        goto end;
    }

    stream_mapping_size = ifmt_ctx->nb_streams;
    stream_mapping = av_mallocz_array(stream_mapping_size, sizeof(*stream_mapping));

    ofmt = ofmt_ctx->oformat;

    for (i = 0; i < ifmt_ctx->nb_streams; i++) {
        AVStream *out_stream;
        AVStream *in_stream = ifmt_ctx->streams[i];
        AVCodecParameters *in_codecpar = in_stream->codecpar;

        if (in_codecpar->codec_type != AVMEDIA_TYPE_AUDIO &&
            in_codecpar->codec_type != AVMEDIA_TYPE_VIDEO &&
            in_codecpar->codec_type != AVMEDIA_TYPE_SUBTITLE) {
            stream_mapping[i] = -1;
            continue;
        }
        stream_mapping[i] = stream_index++;

        out_stream = avformat_new_stream(ofmt_ctx, NULL);
        if (!out_stream) {
            fprintf(stderr, "Failed allocating output stream\n");
            ret = AVERROR_UNKNOWN;
            goto end;
        }

        ret = avcodec_parameters_copy(out_stream->codecpar, in_codecpar);
        if (ret < 0) {
            fprintf(stderr, "Failed to copy codec parameters\n");
            goto end;
        }
        out_stream->codecpar->codec_tag = 0;
    }
    av_dump_format(ofmt_ctx, 0, out_filename, 1);
    if (!(ofmt->flags & AVFMT_NOFILE)) {
        ret = avio_open(&ofmt_ctx->pb, out_filename, AVIO_FLAG_WRITE);
        if (ret < 0) {
            fprintf(stderr, "Could not open output file '%s'", out_filename);
            goto end;
        }
    }

    ret = avformat_write_header(ofmt_ctx, NULL);
    if (ret < 0) {
        fprintf(stderr, "Error occurred when opening output file\n");
        goto end;
    }

    while (1) {
        AVStream *in_stream, *out_stream;

        ret = av_read_frame(ifmt_ctx, &pkt);
        if (ret < 0)
            break;

        in_stream  = ifmt_ctx->streams[pkt.stream_index];
        if (pkt.stream_index >= stream_mapping_size ||
            stream_mapping[pkt.stream_index] < 0) {
            av_packet_unref(&pkt);
            continue;
        }

        pkt.stream_index = stream_mapping[pkt.stream_index];
        out_stream = ofmt_ctx->streams[pkt.stream_index];

            /* copy packet */
        pkt.pts = av_rescale_q_rnd(pkt.pts, in_stream->time_base, out_stream->time_base, AV_ROUND_NEAR_INF|AV_ROUND_PASS_MINMAX);
        pkt.dts = av_rescale_q_rnd(pkt.dts, in_stream->time_base, out_stream->time_base, AV_ROUND_NEAR_INF|AV_ROUND_PASS_MINMAX);
        pkt.duration = av_rescale_q(pkt.duration, in_stream->time_base, out_stream->time_base);
        pkt.pos = -1;

        ret = av_interleaved_write_frame(ofmt_ctx, &pkt);
        if (ret < 0) {
            fprintf(stderr, "Error muxing packet\n");
            break;
        }
        av_packet_unref(&pkt);
    }

    av_write_trailer(ofmt_ctx);
   
end:

    avformat_close_input(&ifmt_ctx);
        /* close output */
    if (ofmt_ctx && !(ofmt->flags & AVFMT_NOFILE)) {
        avio_closep(&ofmt_ctx->pb);
    }
    avformat_free_context(ofmt_ctx);
    av_freep(&stream_mapping);

}

@end
