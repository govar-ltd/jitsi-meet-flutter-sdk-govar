#pragma once
#include "../../tools/aec3/GovarAEC3.h"
#include <array>
#include <atomic>
#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <thread>
#include <chrono>

// Fixed gain with a sample-peak limiter: instant attenuation, 100 ms release.
// No filtering, allocation, or disk work; the final clamp protects PCM16.
class GovarAudioGain {
 public:
  explicit GovarAudioGain(float gain=1.f): gain_(gain) {}
  uint64_t process(int16_t *samples, size_t count) {
    uint64_t limited=0;
    for(size_t i=0;i<count;i++) {
      float value=static_cast<float>(samples[i])*gain_;
      float magnitude=value<0?-value:value;
      float required=magnitude>30000.f?30000.f/magnitude:1.f;
      if(required<attenuation_) attenuation_=required;
      else attenuation_+=(1.f-attenuation_)*0.0002083116f;
      if(attenuation_<0.999f) ++limited;
      samples[i]=static_cast<int16_t>(std::clamp(value*attenuation_,-30000.f,30000.f));
    }
    return limited;
  }
 private:
  float gain_,attenuation_=1.f;
};

// Input and render have separate 10 ms framers. AEC3 accepts one thread per
// direction; lifecycle/reset/flush are called only while RemoteIO is stopped.
class GovarDuplexCore {
 public:
  using Sink = void (*)(void *, const int16_t *, size_t);
  explicit GovarDuplexCore(Sink sink, void *context): sink_(sink), context_(context), apm_(GovarAEC3Create()) {}
  ~GovarDuplexCore() { GovarAEC3Destroy(apm_); }
  bool ready() const { return apm_ != nullptr; }
  void render(const int16_t *p, size_t n) {
    renderSamples.fetch_add(n, std::memory_order_relaxed);
    while(n) { size_t take=std::min(n, 480-renderFill_); std::copy_n(p,take,render_.data()+renderFill_);
      p+=take;n-=take;renderFill_+=take;
      if(renderFill_==480) { if(GovarAEC3Render(apm_,render_.data())) errors++; renderFill_=0; }
    }
  }
  void capture(const int16_t *p, size_t n, int delay) {
    captureSamples.fetch_add(n, std::memory_order_relaxed); lastDelay=delay;
    while(n) { size_t take=std::min(n,480-captureFill_);std::copy_n(p,take,input_.data()+captureFill_);
      p+=take;n-=take;captureFill_+=take;
      if(captureFill_==480) { process(480,delay);captureFill_=0; }
    }
  }
  void flushTail(int delay) {
    if(captureFill_) { const size_t valid=captureFill_;
      std::fill(input_.begin()+valid,input_.end(),0);process(valid,delay);captureFill_=0; }
  }
  void reset() { captureFill_=renderFill_=0; if(GovarAEC3Reset(apm_)) errors++; }
  std::atomic<uint64_t> renderSamples{0},captureSamples{0},processedSamples{0},errors{0};
  std::atomic<int> lastDelay{0};
 private:
  void process(size_t valid,int delay) {
    int result=GovarAEC3Capture(apm_,input_.data(),processed_.data(),delay);
    if(result) { errors++; processed_.fill(0); } // Never send unprotected raw audio on DSP error.
    processedSamples.fetch_add(valid,std::memory_order_relaxed);sink_(context_,processed_.data(),valid);
  }
  Sink sink_; void *context_; void *apm_;
  std::array<int16_t,480> input_{},render_{},processed_{};
  size_t captureFill_=0,renderFill_=0;
};

// One real-time producer, one serial disk consumer. No disk I/O, allocations
// or dispatches occur in append(). Stop/start run with RemoteIO stopped.
class GovarGrowingWav {
 public:
  bool start(const char *path) {
    stop(); file_=fopen(path,"wb+"); if(!file_) { error=1;return false; }
    write_.store(0);read_.store(0);samples_=0;error=0;overruns=0;header();fflush(file_);
    if(error.load()){fclose(file_);file_=nullptr;return false;}
    enabled.store(true,std::memory_order_release);return true;
  }
  void append(const int16_t *p,size_t n) {
    if(!enabled.load(std::memory_order_acquire))return;
    const uint64_t w=write_.load(std::memory_order_relaxed),r=read_.load(std::memory_order_acquire);
    if(n>capacity || w-r+n>capacity) { overruns++;error=2;enabled.store(false);return; }
    for(size_t i=0;i<n;i++)ring_[(w+i)&(capacity-1)]=p[i];
    write_.store(w+n,std::memory_order_release);
  }
  void flush() {
    if(!file_)return;
    uint64_t r=read_.load(std::memory_order_relaxed),w=write_.load(std::memory_order_acquire);
    while(r<w) { size_t n=std::min<uint64_t>(w-r,capacity-(r&(capacity-1)));
      if(samples_+n>(UINT32_MAX-36)/2 || fwrite(ring_.data()+(r&(capacity-1)),2,n,file_)!=n) { error=3;enabled.store(false);break; }
      r+=n;samples_+=n;read_.store(r,std::memory_order_release);
    }
    header();fflush(file_);
  }
  void stop() { enabled.store(false,std::memory_order_release);flush();if(file_){fclose(file_);file_=nullptr;} }
  ~GovarGrowingWav(){stop();}
  double seconds()const{return writtenSamples.load()/48000.;}
  std::atomic<bool> enabled{false};std::atomic<int> error{0};std::atomic<uint64_t> overruns{0},writtenSamples{0};
 private:
  void header() {
    uint8_t h[44]={};memcpy(h,"RIFF",4);memcpy(h+8,"WAVEfmt ",8);memcpy(h+36,"data",4);
    auto u32=[&](int p,uint32_t v){for(int i=0;i<4;i++)h[p+i]=(v>>(8*i))&255;};
    auto u16=[&](int p,uint16_t v){h[p]=v&255;h[p+1]=v>>8;};
    u32(4,36+samples_*2);u32(16,16);u16(20,1);u16(22,1);u32(24,48000);u32(28,96000);u16(32,2);u16(34,16);u32(40,samples_*2);
    if(fseek(file_,0,SEEK_SET)||fwrite(h,1,44,file_)!=44||fseek(file_,0,SEEK_END)) { error=4;enabled.store(false); }
    writtenSamples.store(samples_);
  }
  static constexpr size_t capacity=1<<18;
  std::array<int16_t,capacity> ring_{};std::atomic<uint64_t> write_{0},read_{0};FILE *file_=nullptr;uint64_t samples_=0;
};
