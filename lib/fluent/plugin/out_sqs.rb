require 'fluent/output'
require 'aws-sdk-sqs'

module Fluent
  SQS_BATCH_SEND_MAX_MSGS = 10
  SQS_BATCH_SEND_MAX_SIZE = 262_144

  class SQSOutput < BufferedOutput
    Fluent::Plugin.register_output('sqs', self)

    include SetTagKeyMixin
    config_set_default :include_tag_key, false

    include SetTimeKeyMixin
    config_set_default :include_time_key, true

    config_param :aws_key_id, :string, default: nil, secret: true
    config_param :aws_sec_key, :string, default: nil, secret: true
    config_param :queue_name, :string, default: nil
    config_param :sqs_url, :string, default: nil
    config_param :create_queue, :bool, default: true
    config_param :region, :string, default: 'ap-northeast-1'
    config_param :delay_seconds, :integer, default: 0
    config_param :include_tag, :bool, default: true
    config_param :tag_property_name, :string, default: '__tag'
    config_param :message_group_id, :string, default: nil

    def configure(conf)
      super

      if (!@queue_name.nil? && @queue_name.end_with?('.fifo')) || (!@sqs_url.nil? && @sqs_url.end_with?('.fifo'))
        raise Fluent::ConfigError, 'message_group_id parameter is required for FIFO queue' if @message_group_id.nil?
      end

      Aws.config = {
        access_key_id: @aws_key_id,
        secret_access_key: @aws_sec_key,
        region: @region
      }
    end

    def client
      @client ||= Aws::SQS::Client.new
    end

    def resource
      @resource ||= Aws::SQS::Resource.new(client: client)
    end

    def queue
      return @queue if @queue

      @queue = if @create_queue && @queue_name
                 resource.create_queue(queue_name: @queue_name)
               else
                 @queue = if @sqs_url
                            resource.queue(@sqs_url)
                          else
                            resource.get_queue_by_name(queue_name: @queue_name)
                          end
               end

      @queue
    end

    def format(tag, _time, record)
      record[@tag_property_name] = tag if @include_tag

      record.to_msgpack
    end

    def write(chunk)
      batch_records = []
      batch_size = 0
      send_batches = [batch_records]

      chunk.msgpack_each do |record|
        body = Yajl.dump(record)
        batch_size += body.bytesize

        if batch_size > SQS_BATCH_SEND_MAX_SIZE ||
           batch_records.length >= SQS_BATCH_SEND_MAX_MSGS
          batch_records = []
          batch_size = body.bytesize
          send_batches << batch_records
        end

        if batch_size > SQS_BATCH_SEND_MAX_SIZE
          log.warn 'Could not push message to SQS, payload exceeds ' \
                   "#{SQS_BATCH_SEND_MAX_SIZE} bytes.  " \
                   "(Truncated message: #{body[0..200]})"
        else
          id = "#{@tag_property_name}#{SecureRandom.hex(16)}"
          batch_record = { id: id, message_body: body, delay_seconds: @delay_seconds }
          batch_record[:message_group_id] = @message_group_id unless @message_group_id.nil?
          batch_records << batch_record
        end
      end

      until send_batches.length <= 0
        records = send_batches.shift
        until records.length <= 0
          queue.send_messages(entries: records.slice!(0..9))
        end
      end
    end
  end
end
