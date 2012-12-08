require 'schemata/staging'
require "spec_helper"

describe VCAP::Stager::Client::EmAware do
  # Provides nats_server via let
  include_context :nats_server

  let(:request) { Schemata::Staging.mock_message.contents }

  let(:queue) { "test" }

  describe "#stage" do
    it "should publish the Schemata-encoded request to the supplied queue" do
      decoded_message = nil

      when_nats_connected(nats_server) do |conn|
        handle_request(conn, queue) do |req, reply_to|
          decoded_message = req
          EM.stop
        end

        client = VCAP::Stager::Client::EmAware.new(conn, queue)

        client.stage(request)
      end

      decoded_message.should_not(be_nil)
      decoded_message.should == request
    end

    it "should invoke the error callback when response decoding fails" do
      request_error = nil

      when_nats_connected(nats_server) do |conn|
        handle_request(conn, queue) do |req, reply_to|
          # Invalid json will cause response parsing to fail
          conn.publish(reply_to, "{{}")
        end

        client = VCAP::Stager::Client::EmAware.new(conn, queue)

        deferrable = client.stage(request)

        deferrable.errback do |e|
          request_error = e

          EM.stop
        end
      end

      request_error.should_not be_nil
      request_error.class.should == VCAP::Stager::Client::Error
      request_error.to_s.should match(/Failed decoding/)
    end

    it "should invoke the error callback when a timeout occurs" do
      request_error = nil

      when_nats_connected(nats_server) do |conn|
        client = VCAP::Stager::Client::EmAware.new(conn, queue)

        deferrable = client.stage(request, 0.1)

        deferrable.errback do |e|
          request_error = e

          EM.stop
        end
      end

      request_error.should_not be_nil
      request_error.class.should == VCAP::Stager::Client::Error
      request_error.to_s.should match(/Timed out after/)
    end

    it "should invoke the response callback on a response" do
      exp_resp = { "test" => "resp" }
      recvd_resp = nil

      when_nats_connected(nats_server) do |conn|
        handle_request(conn, queue) do |req, reply_to|
          conn.publish(reply_to, Yajl::Encoder.encode(exp_resp))
        end

        client = VCAP::Stager::Client::EmAware.new(conn, queue)

        deferrable = client.stage(request, 10)

        deferrable.callback do |resp|
          recvd_resp = resp

          EM.stop
        end
      end

      recvd_resp.should == exp_resp
    end
  end
end
