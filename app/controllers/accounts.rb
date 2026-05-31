# frozen_string_literal: true

require 'roda'
require_relative 'app'

module LockedCV
  # Account-scoped API routes
  class Api < Roda
    route('account') do |routing|
      @account_route = "#{@api_root}/account"
      current_account = current_account!(routing)

      routing.on 'password' do
        # PUT api/v1/account/password
        routing.put do
          password_data = HttpRequest.new(routing).body_data
          ChangePasswordService.call(account_id: current_account.id, password_data:)

          { message: 'Password updated' }.to_json
        rescue ChangePasswordService::InvalidCurrentPasswordError
          routing.halt 400, { message: 'Current password is incorrect' }.to_json
        rescue ChangePasswordService::InvalidPasswordError
          routing.halt 400, { message: 'Password is required' }.to_json
        rescue StandardError => e
          Api.logger.error "UNKNOWN ERROR: #{e.message}"
          routing.halt 500, { message: 'Database error' }.to_json
        end
      end

      # PUT api/v1/account
      routing.put do
        updated_data = HttpRequest.new(routing).body_data
        account = UpdateAccountService.call(account_id: current_account.id, account_data: updated_data)

        { message: 'Account updated', data: account }.to_json
      rescue Sequel::MassAssignmentRestriction
        Api.logger.warn("MASS_ASSIGNMENT_ATTEMPT keys=#{updated_data.keys}")
        routing.halt 400, { message: 'Illegal attributes' }.to_json
      rescue StandardError => e
        Api.logger.error "UNKNOWN ERROR: #{e.message}"
        routing.halt 500, { message: 'Database error' }.to_json
      end

      # GET api/v1/account
      routing.get do
        current_account.to_json
      end
    end

    route('accounts') do |routing|
      @account_route = "#{@api_root}/accounts"

      routing.on 'registration' do
        routing.is 'check' do
          # POST api/v1/accounts/registration/check
          routing.post do
            registration = HttpRequest.new(routing).body_data
            CheckRegistrationAvailability.new(registration).call

            { available: true }.to_json
          rescue CheckRegistrationAvailability::InvalidRegistration => e
            routing.halt 400, { message: e.message }.to_json
          rescue StandardError => e
            Api.logger.error "UNKNOWN ERROR: #{e.message}"
            routing.halt 500, { message: 'Unknown server error' }.to_json
          end
        end
      end

      routing.on String do |account_id|
        routing.on 'system_roles' do
          routing.on String do |role_name|
            # PUT api/v1/accounts/[username]/system_roles/[role_name]
            routing.put do
              current_account = current_account!(routing)
              auth_scope = current_auth_scope!(routing)
              routing.halt 400, { message: 'Unknown system role' }.to_json unless Role::SYSTEM_ROLES.include?(role_name)

              target_account = Account.first(username: account_id)
              routing.halt 404, { message: 'Account not found' }.to_json unless target_account
              unless AccountPolicy.new(current_account, target_account, auth_scope:).assign_system_role?
                message = current_account.id == target_account.id ? 'Admins cannot change their own system role' : 'Only admins can manage system roles'
                routing.halt 403, { message: }.to_json
              end

              result = AssignSystemRoleService.call(
                current_account:, target_username: account_id, role_name:
              )

              response.status = result.created? ? 201 : 200
              { message: 'System role assigned', data: result.account }.to_json
            rescue AssignSystemRoleService::NotAuthorizedError => e
              routing.halt 403, { message: e.message }.to_json
            rescue AssignSystemRoleService::UnknownRoleError
              routing.halt 400, { message: 'Unknown system role' }.to_json
            rescue AssignSystemRoleService::UnknownAccountError
              routing.halt 404, { message: 'Account not found' }.to_json
            rescue StandardError => e
              Api.logger.error "UNKNOWN ERROR: #{e.message}"
              routing.halt 500, { message: 'Database error' }.to_json
            end
          end
        end

        # DELETE api/v1/accounts/[account_id]
        routing.delete do
          current_account = current_account!(routing)
          auth_scope = current_auth_scope!(routing)
          target_account = Account.first(id: account_id)
          routing.halt 404, { message: 'Account not found' }.to_json unless target_account
          unless AccountPolicy.new(current_account, target_account, auth_scope:).delete?
            message = current_account.id == target_account.id ? 'Admins cannot delete their own account' : 'Only admins can delete accounts'
            routing.halt 403, { message: }.to_json
          end

          DeleteAccountService.call(
            current_account:,
            target_account_id: account_id
          )

          { message: 'Account deleted' }.to_json
        rescue DeleteAccountService::NotAuthorizedError
          routing.halt 403, { message: 'Only admins can delete accounts' }.to_json
        rescue DeleteAccountService::CannotDeleteSelfError
          routing.halt 403, { message: 'Admins cannot delete their own account' }.to_json
        rescue DeleteAccountService::AccountNotFoundError
          routing.halt 404, { message: 'Account not found' }.to_json
        rescue StandardError => e
          Api.logger.error "UNKNOWN ERROR: #{e.message}"
          routing.halt 500, { message: 'Database error' }.to_json
        end
      end

      # GET api/v1/accounts
      routing.get do
        current_account = current_account!(routing)
        auth_scope = current_auth_scope!(routing)
        unless AccountPolicy.new(current_account, current_account, auth_scope:).capabilities[:can_manage_accounts]
          routing.halt 403, { message: 'Only admins can list accounts' }.to_json
        end
        accounts = AccountPolicy::AdminScope.new(current_account, Account.order(:username)).viewable.all

        output = {
          data: accounts.map do |account|
            {
              type: 'account',
              attributes: {
                id: account.id,
                username: account.username,
                email: account.email,
                roles: account.system_roles.map(&:name)
              }
            }
          end
        }
        JSON.pretty_generate(output)
      rescue ListAccountsService::NotAuthorizedError
        routing.halt 403, { message: 'Only admins can list accounts' }.to_json
      rescue StandardError => e
        Api.logger.error "UNKNOWN ERROR: #{e.message}"
        routing.halt 500, { message: 'Database error' }.to_json
      end

      # POST api/v1/accounts
      routing.post do
        new_data = HttpRequest.new(routing).body_data
        new_doc = CreateAccountService.call(account_data: new_data)

        response.status = 201
        response['Location'] = "#{@account_route}/#{new_doc.id}"
        { message: 'Account saved', data: new_doc }.to_json
      rescue Sequel::MassAssignmentRestriction
        Api.logger.warn("MASS_ASSIGNMENT_ATTEMPT keys=#{new_data.keys}")
        routing.halt 400, { message: 'Illegal attributes' }.to_json
      rescue Sequel::UniqueConstraintViolation
        routing.halt 400, { message: 'This user is already registered' }.to_json
      rescue StandardError => e
        Api.logger.error "UNKNOWN ERROR: #{e.message}"
        routing.halt 500, { message: 'Database error' }.to_json
      end
    end

    private

    def authenticated_account!(routing)
      token = authenticated_token!(routing)
      token.payload
    end

    def authenticated_token!(routing)
      token = HttpRequest.new(routing).authenticated_token
      routing.halt 401, { message: 'Missing authorization token' }.to_json unless token

      token
    rescue AuthToken::ExpiredTokenError
      routing.halt 401, { message: 'Expired authorization token' }.to_json
    rescue AuthToken::InvalidTokenError
      routing.halt 401, { message: 'Invalid authorization token' }.to_json
    end

    def current_auth_scope!(routing)
      AuthScope.new(authenticated_token!(routing).scope)
    end

    def current_account!(routing)
      payload = authenticated_account!(routing)
      account = Account.first(id: payload['account_id'])
      return account if account

      routing.halt 401, { message: 'Invalid authorization token' }.to_json
    end

    def require_owner!(routing, account_id)
      current_account = authenticated_account!(routing)
      return current_account if current_account['account_id'] == account_id

      routing.halt 403, { message: 'Forbidden account access' }.to_json
    end

    def require_admin!(routing, forbidden_message = 'Only admins can perform this action')
      account = current_account!(routing)
      return account if account&.admin?

      routing.halt 403, { message: forbidden_message }.to_json
    end

  end
end
