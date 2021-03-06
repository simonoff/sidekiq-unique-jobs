require 'spec_helper'
require 'sidekiq/worker'
require 'sidekiq-unique-jobs'
require 'sidekiq/scheduled'
require 'sidekiq_unique_jobs/middleware/server/unique_jobs'
require 'active_support/core_ext/time'
require 'active_support/testing/time_helpers'
require 'rspec-sidekiq'

describe 'When Sidekiq::Testing is enabled' do
  describe 'when set to :fake!', sidekiq: :fake do

    # Flush db before each test
    before :each do
      Sidekiq.redis(&:flushdb)
    end
    context 'with unique worker' do
      it 'does not push duplicate messages' do
        param = 'work'
        expect(UniqueWorker.jobs.size).to eq(0)
        expect(UniqueWorker.perform_async(param)).to_not be_nil
        expect(UniqueWorker.jobs.size).to eq(1)
        expect(UniqueWorker).to have_enqueued_job(param)
        expect(UniqueWorker.perform_async(param)).to be_nil
        expect(UniqueWorker.jobs.size).to eq(1)
      end

      it 'adds the unique_hash to the message' do
        param = 'hash'
        hash = SidekiqUniqueJobs::PayloadHelper.get_payload(UniqueWorker, :working, [param])
        expect(UniqueWorker.perform_async(param)).to_not be_nil
        expect(UniqueWorker.jobs.size).to eq(1)
        expect(UniqueWorker.jobs.first['unique_hash']).to eq(hash)
      end
    end

    context 'with non-unique worker' do
      it 'pushes duplicates messages' do
        param = 'work'
        expect(MyWorker.jobs.size).to eq(0)
        MyWorker.perform_async(param)
        expect(MyWorker.jobs.size).to eq(1)
        expect(MyWorker).to have_enqueued_job(param)
        MyWorker.perform_async(param)
        expect(MyWorker.jobs.size).to eq(2)
      end
    end
  end

  describe 'when set to :inline!', sidekiq: :inline do
    class InlineWorker
      include Sidekiq::Worker
      sidekiq_options unique: true

      def perform(x)
        TestClass.run(x)
      end
    end

    class InlineUnlockOrderWorker
      include Sidekiq::Worker
      sidekiq_options unique: true, unique_unlock_order: :never

      def perform(x)
        TestClass.run(x)
      end
    end

    class InlineUnlockOrderWorker
      include Sidekiq::Worker
      sidekiq_options unique: true, unique_unlock_order: :never

      def perform(x)
        TestClass.run(x)
      end
    end

    class InlineExpirationWorker
      include Sidekiq::Worker
      sidekiq_options unique: true, unique_unlock_order: :never,
                      unique_job_expiration: 10 * 60
      def perform(x)
        TestClass.run(x)
      end
    end

    class TestClass
      def self.run(_x)
      end
    end

    it 'once the job is completed allows to run another one' do
      expect(TestClass).to receive(:run).exactly(2).times

      InlineWorker.perform_async('test')
      InlineWorker.perform_async('test')
    end

    it 'if the unique is kept forever it does not allows to run the job again' do
      expect(TestClass).to receive(:run).once

      InlineUnlockOrderWorker.perform_async('test')
      InlineUnlockOrderWorker.perform_async('test')
    end

    describe 'when a job is set to run once in 10 minutes' do
      include ActiveSupport::Testing::TimeHelpers
      it 'only allows 1 call per 10 minutes' do
        allow(TestClass).to receive(:run).with(1).and_return(true)
        allow(TestClass).to receive(:run).with(2).and_return(true)

        InlineExpirationWorker.perform_async(1)
        expect(TestClass).to have_received(:run).with(1).once
        100.times do
          InlineExpirationWorker.perform_async(1)
        end
        expect(TestClass).to have_received(:run).with(1).once
        InlineExpirationWorker.perform_async(2)
        expect(TestClass).to have_received(:run).with(1).once
        expect(TestClass).to have_received(:run).with(2).once
        travel_to(Time.now + (11 * 60)) do
          InlineExpirationWorker.perform_async(1)
        end

        expect(TestClass).to have_received(:run).with(1).twice
      end
    end
  end
end
