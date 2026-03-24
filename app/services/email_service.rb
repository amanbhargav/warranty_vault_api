# frozen_string_literal: true

# Service for handling all email operations
class EmailService
  class << self
    # Send verification email
    def send_verification_email(user)
      return false unless user&.email

      begin
        # Generate token and save it
        token = VerificationService.generate_verification_token(user)
        VerificationMailer.verification_email(user, token).deliver_now
        Rails.logger.info "[EmailService] Verification email sent to #{user.email}"
        true
      rescue => e
        Rails.logger.error "[EmailService] Failed to send verification email: #{e.message}"
        false
      end
    end

    # Send daily reminder email
    def send_daily_reminder(user)
      return false unless user&.email_verified?

      begin
        NotificationMailer.daily_reminder(user).deliver_now
        Rails.logger.info "[EmailService] Daily reminder sent to #{user.email}"
        true
      rescue => e
        Rails.logger.error "[EmailService] Failed to send daily reminder: #{e.message}"
        false
      end
    end

    # Send warranty expiry notification
    def send_warranty_notification(user, warranties)
      return false unless user&.email_verified? || warranties.empty?

      begin
        NotificationMailer.warranty_expiry_notification(user, warranties).deliver_now
        Rails.logger.info "[EmailService] Warranty notification sent to #{user.email}"
        true
      rescue => e
        Rails.logger.error "[EmailService] Failed to send warranty notification: #{e.message}"
        false
      end
    end

    # Send app reminder email
    def send_app_reminder(user)
      return false unless user&.email_verified?

      begin
        NotificationMailer.app_reminder(user).deliver_now
        Rails.logger.info "[EmailService] App reminder sent to #{user.email}"
        true
      rescue => e
        Rails.logger.error "[EmailService] Failed to send app reminder: #{e.message}"
        false
      end
    end

    # Send welcome email
    def send_welcome_email(user)
      return false unless user&.email_verified?

      begin
        NotificationMailer.welcome_email(user).deliver_now
        Rails.logger.info "[EmailService] Welcome email sent to #{user.email}"
        true
      rescue => e
        Rails.logger.error "[EmailService] Failed to send welcome email: #{e.message}"
        false
      end
    end

    # Handle email delivery failures
    def handle_delivery_failure(email, error)
      Rails.logger.error "[EmailService] Email delivery failed for #{email}: #{error}"

      # Log to monitoring system
      # Could integrate with services like Sentry, Rollbar, etc.

      # Optionally notify admin
      # AdminMailer.delivery_failure_notification(email, error).deliver_later
    end

    # Check email configuration
    def email_configured?
      Rails.application.config.action_mailer.delivery_method != :test
    end
  end
end
