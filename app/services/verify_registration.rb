# frozen_string_literal: true

require 'http'

module LockedCV
  # Sends a verification email to a prospective account-holder so that
  # only someone who can read the inbox can finish account creation.
  # Wraps Mailgun's POST /messages endpoint with Basic auth.
  class VerifyRegistration
    class InvalidRegistration < StandardError; end
    class EmailProviderError < StandardError; end

    def initialize(registration)
      @registration = registration
    end

    def call
      validate_required_fields!
      check_availability!

      send_email
      @registration
    end

    private

    def validate_required_fields!
      raise InvalidRegistration, 'Email is required' if registration_value(:email).empty?
      raise InvalidRegistration, 'Username is required' if registration_value(:username).empty?
      raise InvalidRegistration, 'Verification URL is required' if registration_value(:verification_url).empty?
    end

    def check_availability!
      CheckRegistrationAvailability.new(@registration).call
    rescue CheckRegistrationAvailability::InvalidRegistration => e
      raise InvalidRegistration, e.message
    end

    def registration_value(key)
      @registration[key].to_s.strip
    end

    def send_email
      response = HTTP
                 .basic_auth(user: 'api', pass: api_key)
                 .post(mail_url, form: mail_form)
      return if response.status < 300

      Api.logger.error("Mailgun error #{response.status}: #{response.body}")
      raise EmailProviderError, 'Email provider rejected the request'
    rescue HTTP::Error => e
      Api.logger.error("Mailgun request failed: #{e.message}")
      raise EmailProviderError, 'Email provider rejected the request'
    end

    def api_key = ENV.fetch('MAILGUN_API_KEY')
    def mail_api_url = ENV.fetch('MAILGUN_API_URL', 'https://api.mailgun.net/v3')
    def mailgun_domain = ENV.fetch('MAILGUN_DOMAIN').to_s.strip
    def mail_url = "#{mail_api_url.delete_suffix('/')}/#{mailgun_domain}/messages"
    def from_email = ENV.fetch('MAILGUN_FROM_EMAIL')
    def from_name = ENV.fetch('MAILGUN_FROM_NAME', 'LockedCV')

    def mail_form
      {
        from: "#{from_name} <#{from_email}>",
        to: registration_value(:email),
        subject: 'LockedCV Registration Verification',
        html: html_body
      }
    end

    def html_body
      <<~HTML
        <h2>Welcome to LockedCV, #{registration_value(:username)}!</h2>
        <p>Click the link below to finish creating your account:</p>
        <p><a href="#{registration_value(:verification_url)}">Verify your registration</a></p>
        <p>If you didn't request this, you can safely ignore this email.</p>
      HTML
    end
  end
end
