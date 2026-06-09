# frozen_string_literal: true

require_relative '../spec_helper'

describe 'Signed request library' do
  before do
    @original_verify_key = LockedCV::SignedRequest.instance_variable_get(:@verify_key)
    @original_signing_key = LockedCV::SignedRequest.instance_variable_get(:@signing_key)
    @keypair = LockedCV::SignedRequest.generate_keypair
    LockedCV::SignedRequest.setup(@keypair[:verify_key], @keypair[:signing_key])
    @message = { username: 'vick', nested: { email: 'vick@example.com' } }
  end

  after do
    LockedCV::SignedRequest.instance_variable_set(:@verify_key, @original_verify_key)
    LockedCV::SignedRequest.instance_variable_set(:@signing_key, @original_signing_key)
  end

  it 'HAPPY: signs and parses a message' do
    signed = LockedCV::SignedRequest.sign(@message)

    _(LockedCV::SignedRequest.parse(signed)).must_equal @message
  end

  it 'BAD: rejects tampered data' do
    signed = LockedCV::SignedRequest.sign(@message)
    signed[:data] = signed[:data].merge(username: 'attacker')

    _ do
      LockedCV::SignedRequest.parse(signed)
    end.must_raise LockedCV::SignedRequest::VerificationError
  end

  it 'BAD: rejects missing signatures' do
    _ do
      LockedCV::SignedRequest.parse(data: @message)
    end.must_raise LockedCV::SignedRequest::VerificationError
  end

  it 'BAD: rejects invalid setup keys' do
    _ do
      LockedCV::SignedRequest.setup('not-base64')
    end.must_raise LockedCV::SignedRequest::KeypairError
  end

  it 'SECURITY: cannot sign when only verify key is configured' do
    LockedCV::SignedRequest.setup(@keypair[:verify_key])

    _ do
      LockedCV::SignedRequest.sign(@message)
    end.must_raise LockedCV::SignedRequest::KeypairError
  end
end
