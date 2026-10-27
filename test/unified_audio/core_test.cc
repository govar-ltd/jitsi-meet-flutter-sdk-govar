#include "../../ios/Classes/GovarDuplexCore.hpp"
#include <cassert>
#include <cmath>
#include <vector>
#include <iostream>
#include <fstream>
#include <random>
struct Collector { std::vector<int16_t> pcm; static void accept(void *p,const int16_t *s,size_t n){auto *self=static_cast<Collector*>(p);self->pcm.insert(self->pcm.end(),s,s+n);} };
static void continuity(const char *path) {
 Collector sink;GovarDuplexCore pipe(Collector::accept,&sink);assert(pipe.ready());
 std::vector<int16_t> samples(48000*8+137),silence(4096);
 for(size_t i=0;i<samples.size();i++)samples[i]=(int16_t)(2000*sin(i*.2));
 size_t offset=0;const size_t sizes[]={1,127,240,480,512,960,4096,17};size_t k=0;
 while(offset<samples.size()) { size_t n=std::min(sizes[k++%8],samples.size()-offset);pipe.render(silence.data(),n);pipe.capture(samples.data()+offset,n,20);offset+=n; }
 pipe.flushTail(20);assert(sink.pcm.size()==samples.size());assert(pipe.errors==0);
 GovarGrowingWav wav;assert(wav.start(path));
 offset=0;while(offset<sink.pcm.size()) { size_t n=std::min<size_t>(1537,sink.pcm.size()-offset);wav.append(sink.pcm.data()+offset,n);wav.flush();offset+=n; }
 wav.stop();assert(wav.error==0);assert(wav.writtenSamples==samples.size());
 std::ifstream file(path,std::ios::binary);std::vector<char> bytes((std::istreambuf_iterator<char>(file)),{});
 assert(bytes.size()==44+samples.size()*2);assert(!memcmp(bytes.data(),"RIFF",4));
 assert(!memcmp(bytes.data()+44,sink.pcm.data(),samples.size()*2));
 assert(!wav.start("/definitely_missing_govar_directory/file.wav"));
 std::cout<<"PASS: irregular callback sizes, padded final tail, growing WAV PCM exact; "<<samples.size()<<" samples\n";
}
static void echo() {
 void *apm=GovarAEC3Create();assert(apm);std::mt19937 random(42);std::uniform_real_distribution<float> noise(-1,1);
 std::vector<int16_t> reference(48000*16);float color=0;
 for(auto &s:reference){color=.7f*color+.3f*noise(random);s=(int16_t)(color*20000);}
 int16_t capture[480],output[480];double before=0,after=0;
 for(int frame=0;frame<1600;frame++) {
  int offset=frame*480;assert(GovarAEC3Render(apm,reference.data()+offset)==0);
  for(int j=0;j<480;j++){int i=offset+j;capture[j]=i>=1440?(int16_t)(reference[i-1440]*.55):0;}
  assert(GovarAEC3Capture(apm,capture,output,30)==0);
  if(frame>1200)for(int j=0;j<480;j++){before+=(double)capture[j]*capture[j];after+=(double)output[j]*output[j];}
 }
 double reduction=10*log10(before/std::max(after,1.));std::cout<<"Synthetic echo reduction: "<<reduction<<" dB\n";assert(reduction>15);
 GovarAEC3Destroy(apm);
}
static void highBand() {
 void *apm=GovarAEC3Create();int16_t input[480],zero[480]={},output[480];double before=0,after=0;
 for(int frame=0;frame<400;frame++) {
  for(int j=0;j<480;j++)input[j]=(int16_t)(4000*sin(2*3.141592653589793*17000*(frame*480+j)/48000.));
  assert(GovarAEC3Render(apm,zero)==0);assert(GovarAEC3Capture(apm,input,output,20)==0);
  if(frame>200)for(int j=0;j<480;j++){before+=(double)input[j]*input[j];after+=(double)output[j]*output[j];}
 }
 double ratio=sqrt(after/before);std::cout<<"17 kHz input/output RMS ratio: "<<ratio<<"\n";assert(ratio>.75);GovarAEC3Destroy(apm);
}
static void doubleTalk() {
 void *apm=GovarAEC3Create();assert(apm);std::mt19937 rng(7);std::uniform_real_distribution<float> noise(-1,1);
 std::vector<int16_t> far(48000*20);float color=0;
 for(auto &v:far){color=.6f*color+.4f*noise(rng);v=(int16_t)(color*22000);}
 int16_t input[480],out[480];double sine=0,cosine=0;int measured=0;
 for(int frame=0;frame<2000;frame++) {
  int offset=frame*480;assert(GovarAEC3Render(apm,far.data()+offset)==0);
  for(int j=0;j<480;j++) {
   int i=offset+j;double echo=i>=960?far[i-960]*.7:0;
   double near=frame>=1200?6000*sin(2*3.141592653589793*997*i/48000.):0;
   input[j]=(int16_t)std::clamp(echo+near,-30000.,30000.);
  }
  assert(GovarAEC3Capture(apm,input,out,20)==0);
  if(frame>=1500)for(int j=0;j<480;j++) {double phase=2*3.141592653589793*997*(offset+j)/48000.;sine+=out[j]*sin(phase);cosine+=out[j]*cos(phase);measured++;}
 }
 double nearGain=2*sqrt(sine*sine+cosine*cosine)/measured/6000.;
 std::cout<<"Double-talk near-end tone amplitude ratio: "<<nearGain<<"\n";assert(nearGain>.35);GovarAEC3Destroy(apm);
}
int main(int argc,char **argv){continuity(argv[1]);echo();highBand();doubleTalk();std::cout<<"All unified AEC3 core checks passed\n";}
