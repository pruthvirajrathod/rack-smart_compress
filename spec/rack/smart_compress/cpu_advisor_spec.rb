# frozen_string_literal: true

require "spec_helper"

RSpec.describe Rack::SmartCompress::CpuAdvisor do
  after do
    described_class.reset!
  end

  describe ".adjusted_level" do
    context "under normal load" do
      before do
        allow(described_class).to receive(:high_load?).and_return(false)
      end

      it "preserves default levels" do
        expect(described_class.adjusted_level("zstd", 5)).to eq(5)
        expect(described_class.adjusted_level("br", 6)).to eq(6)
        expect(described_class.adjusted_level("gzip", 9)).to eq(9)
      end
    end

    context "under high load" do
      before do
        allow(described_class).to receive(:high_load?).and_return(true)
      end

      it "drops compression levels to fast presets" do
        expect(described_class.adjusted_level("zstd", 5)).to eq(1)
        expect(described_class.adjusted_level("br", 6)).to eq(1)
        expect(described_class.adjusted_level("gzip", 9)).to eq(Zlib::BEST_SPEED)
        expect(described_class.adjusted_level("deflate", 9)).to eq(Zlib::BEST_SPEED)
      end
    end
  end

  describe "throttling" do
    it "samples load at most once per second" do
      described_class.reset!
      expect(described_class).to receive(:compute_high_load).once.and_return(false)

      # 1st check
      described_class.high_load?
      # 2nd immediate check within cooldown
      described_class.high_load?
    end
  end
end
