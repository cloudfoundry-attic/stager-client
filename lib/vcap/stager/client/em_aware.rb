require "eventmachine"
require "schemata/staging"
require "yajl"

require "vcap/stager/client/errors"

module VCAP
  module Stager
    module Client
    end
  end
end

class VCAP::Stager::Client::EmAware
  # @param [NATS]    Nats connection to use as transport
  # @param [String]  Queue to publish the request to
  def initialize(nats, queue)
    @nats  = nats
    @queue = queue
  end

  # Requests that an application be staged
  #
  # @param [Hash] request_details
  # @param [Integer] How long to wait for a response
  #
  # @return [EM::DefaultDeferrable]
  def stage(request_details, timeout_secs = 120)
    msg_obj = Schemata::Staging::Message::V1.new(request_details)
    encoded_msg = msg_obj.encode

    deferrable = EM::DefaultDeferrable.new

    sid = @nats.request(@queue, encoded_msg) do |result|
      begin
        decoded_result = Yajl::Parser.parse(result)
      rescue => e
        emsg = "Failed decoding response: #{e}"
        deferrable.fail(VCAP::Stager::Client::Error.new(emsg))
        next
      end

      # Needs to be outside the begin-rescue-end block to ensure that #fulfill
      # doesn't cause #fail to be called.
      deferrable.succeed(decoded_result)
    end

    @nats.timeout(sid, timeout_secs) do
      err = VCAP::Stager::Client::Error.new("Timed out after #{timeout_secs}s.")
      deferrable.fail(err)
    end

    deferrable
  end
end
