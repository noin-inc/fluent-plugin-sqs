require 'spec_helper'
require 'fluent/plugin/out_sqs'

describe Fluent::SQSOutput do
  let(:driver) { Fluent::Test::BufferedOutputTestDriver.new(Fluent::SQSOutput) }
  subject { driver.instance }

  before { Fluent::Test.setup }

  describe '#configure' do
    let(:config) do
      %(
         aws_key_id AWS_KEY_ID
         aws_sec_key AWS_SEC_KEY
         queue_name QUEUE_NAME
         sqs_url http://SQS_URL
         create_queue false
         region REGION
         delay_seconds 1
         include_tag false
         tag_property_name TAG_PROPERTY_NAME
         message_group_id MESSAGE_GROUP_ID
      )
    end

    context 'fluentd output configuration settings' do
      before { driver.configure(config) }

      it { expect(subject.aws_key_id).to eq('AWS_KEY_ID') }
      it { expect(subject.aws_sec_key).to eq('AWS_SEC_KEY') }
      it { expect(subject.queue_name).to eq('QUEUE_NAME') }
      it { expect(subject.sqs_url).to eq('http://SQS_URL') }
      it { expect(subject.create_queue).to eq(false) }
      it { expect(subject.region).to eq('REGION') }
      it { expect(subject.delay_seconds).to eq(1) }
      it { expect(subject.include_tag).to eq(false) }
      it { expect(subject.tag_property_name).to eq('TAG_PROPERTY_NAME') }
      it { expect(subject.message_group_id).to eq('MESSAGE_GROUP_ID') }
    end

    context 'AWS configuration settings' do
      subject { Aws.config }

      before do
        driver.instance
        driver.configure(config)
      end

      it { expect(subject[:access_key_id]).to eq('AWS_KEY_ID') }
      it { expect(subject[:secret_access_key]).to eq('AWS_SEC_KEY') }
      it { expect(subject[:region]).to eq('REGION') }
    end

    context 'using Standard queue' do
      let(:config) { %( queue_name QUEUE_NAME ) }

      it 'does not raises error' do
        expect { driver.configure(config) }.not_to raise_error(Fluent::ConfigError)
      end
    end

    context 'using FIFO queue and sets message_group_id' do
      let(:config) do
        %(
          queue_name QUEUE_NAME.fifo
          message_group_id MESSAGE_GROUP_ID
        )
      end

      it 'does not raise error' do
        expect { driver.configure(config) }.not_to raise_error(Fluent::ConfigError)
      end
    end

    context 'using FIFO queue and does not set message_group_id' do
      let(:config) { %( queue_name QUEUE_NAME.fifo ) }

      it 'raises error' do
        expect { driver.configure(config) }.to raise_error(Fluent::ConfigError)
      end
    end
  end

  describe '#queue' do
    before { driver.configure(config) }

    context 'when create_queue and queue_name are set' do
      let(:config) do
        %(
         queue_name QUEUE_NAME
         create_queue true
        )
      end
      let(:resource_instance) { double(:resource_instance) }
      let(:queue) { double(:queue) }

      before { allow(subject).to receive(:resource) { resource_instance } }

      it 'calls on create_queue with queue_name' do
        expect(resource_instance).to receive(:create_queue).with(queue_name: 'QUEUE_NAME') { queue }

        expect(subject.queue).to eq(queue)
      end
    end

    context 'when create_queue is not set but a sqs_url is' do
      let(:config) do
        %(
         queue_name QUEUE_NAME
         create_queue false
         sqs_url SQS_URL
        )
      end
      let(:resource_instance) { double(:resource_instance) }
      let(:queue) { double(:queue) }

      before { allow(subject).to receive(:resource) { resource_instance } }

      it 'gets queue from sqs_url' do
        expect(resource_instance).to receive(:queue).with('SQS_URL') { queue }

        expect(subject.queue).to eq(queue)
      end
    end

    context 'when create_queue is not set nor sqs_url' do
      let(:config) do
        %(
         queue_name QUEUE_NAME
         create_queue false
        )
      end
      let(:resource_instance) { double(:resource_instance) }
      let(:queue) { double(:queue) }

      before { allow(subject).to receive(:resource) { resource_instance } }

      it 'gets queue from queue_name' do
        expect(resource_instance).to receive(:get_queue_by_name).with(queue_name: 'QUEUE_NAME') { queue }

        expect(subject.queue).to eq(queue)
      end
    end
  end

  describe '#write' do
    before { driver.configure(config) }

    let(:config) do
      %(
       queue_name QUEUE_NAME
      )
    end

    let(:record) { {} }
    let(:body) { double(:body, bytesize: 1) }

    it 'send_messages to queue' do
      allow(Yajl).to receive(:dump).with(record) { body }

      expect(driver.instance).to receive(:queue).twice.and_return("QUEUE_NAME")
      expect(subject.queue).to receive(:send_messages).with(entries: [{ id: kind_of(String), message_body: body, delay_seconds: 0 }])

      driver.emit(record).run
    end
  end
end
