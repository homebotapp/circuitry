require 'spec_helper'

RSpec.describe Concord::Subscriber, type: :model do
  subject { described_class.new(queue, options) }

  let(:queue) { 'https://sqs.amazon.com/account/queue' }
  let(:options) { {} }

  describe '#subscribe' do
    describe 'when queue is not set' do
      let(:queue) { nil }
      let(:block) { ->{ } }

      it 'raises an error' do
        expect { subject.subscribe(queue, &block) }.to raise_error(ArgumentError)
      end
    end

    describe 'when block is not given' do
      let(:queue) { 'https://sqs.amazon.com/account/queue' }

      it 'raises an error' do
        expect { subject.subscribe(queue) }.to raise_error(ArgumentError)
      end
    end

    describe 'when queue and block are set' do
      let(:queue) { 'https://sqs.amazon.com/account/queue' }
      let(:block) { ->(_, _) { } }
      let(:mock_sqs) { double('SQS', receive_message: double('Response', body: { 'Message' => messages })) }
      let(:mock_logger) { double('Logger', info: nil, warn: nil, error: nil) }
      let(:messages) { [] }

      before do
        allow(subject).to receive(:sqs).and_return(mock_sqs)
        allow(subject).to receive(:logger).and_return(mock_logger)
        allow(subject).to receive(:loop) do |&block|
          block.call
        end
      end

      describe 'when AWS credentials are set' do
        before do
          allow(subject).to receive(:can_subscribe?).and_return(true)
        end

        it 'subscribes to SQS' do
          subject.subscribe(&block)
          expect(mock_sqs).to have_received(:receive_message).with(queue, any_args)
        end

        describe 'when messages are received' do
          let(:messages) do
            [
                { 'MessageId' => 'one', 'ReceiptHandle' => 'delete-one', 'Body' => { 'Message' => 'Foo'.to_json, 'TopicArn' => 'arn:aws:sns:us-east-1:123456789012:test-event-task-changed' }.to_json },
                { 'MessageId' => 'two', 'ReceiptHandle' => 'delete-two', 'Body' => { 'Message' => 'Bar'.to_json, 'TopicArn' => 'arn:aws:sns:us-east-1:123456789012:test-event-comment' }.to_json },
            ]
          end

          before do
            allow(mock_sqs).to receive(:delete_message)
          end

          it 'processes each message' do
            expect(block).to receive(:call).with('Foo', 'test-event-task-changed')
            expect(block).to receive(:call).with('Bar', 'test-event-comment')
            subject.subscribe(&block)
          end

          it 'deletes each message' do
            subject.subscribe(&block)
            expect(mock_sqs).to have_received(:delete_message).with(queue, 'delete-one')
            expect(mock_sqs).to have_received(:delete_message).with(queue, 'delete-two')
          end

          describe 'when processing fails' do
            let(:block) { ->(message, topic) { raise error if message == 'Foo' } }
            let(:error) { StandardError.new('test error') }

            it 'does not raise the error' do
              expect { subject.subscribe(&block) }.to_not raise_error
            end

            it 'logs error for failing messages' do
              subject.subscribe(&block)
              expect(mock_logger).to have_received(:error).with('Error handling message one: test error')
            end

            it 'does not log error for successful messages' do
              subject.subscribe(&block)
              expect(mock_logger).to_not have_received(:error).with('Error handling message two: test error')
            end

            it 'deletes successful messages' do
              subject.subscribe(&block)
              expect(mock_sqs).to have_received(:delete_message).with(queue, 'delete-two')
            end

            it 'does not delete failing messages' do
              subject.subscribe(&block)
              expect(mock_sqs).to_not have_received(:delete_message).with(queue, 'delete-one')
            end

            describe 'when error logger is configured' do
              let(:error_handler) { ->(_) { } }

              before do
                allow(subject).to receive(:error_handler).and_return(error_handler)
              end

              it 'calls error handler' do
                expect(error_handler).to receive(:call).with(error)
                subject.subscribe(&block)
              end
            end
          end
        end
      end

      describe 'when AWS credentials are not set' do
        before do
          allow(subject).to receive(:can_subscribe?).and_return(false)
          allow(subject).to receive(:logger).and_return(logger)
        end

        let(:logger) { double('Logger', warn: true) }

        it 'does not subscribe to SNS' do
          subject.subscribe(&block)
          expect(mock_sqs).to_not have_received(:receive_message).with(queue, any_args)
        end

        it 'logs a warning' do
          subject.subscribe(&block)
          expect(logger).to have_received(:warn).with('Concord unable to subscribe: AWS configuration is not set.')
        end
      end
    end
  end
end
