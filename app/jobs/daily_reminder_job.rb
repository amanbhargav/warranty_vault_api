# frozen_string_literal: true

# Background job to send daily reminder emails
class DailyReminderJob < ApplicationJob
  queue_as :daily_reminders

  # Retry configuration
  retry_on StandardError, wait: :exponentially_longer, attempts: 3
  discard_on ActiveRecord::RecordNotFound

  def perform(*args)
    start_time = Time.current

    Rails.logger.info "[DailyReminderJob] ===== STARTING DAILY REMINDERS ====="
    Rails.logger.info "[DailyReminderJob] Started at: #{start_time}"

    # Get all verified users
    verified_users = User.where(email_verified: true)

    Rails.logger.info "[DailyReminderJob] Processing #{verified_users.count} verified users"

    success_count = 0
    failure_count = 0

    verified_users.find_each do |user|
      begin
        # Send daily reminder email
        if EmailService.send_daily_reminder(user)
          success_count += 1
          Rails.logger.info "[DailyReminderJob] ✅ Sent reminder to #{user.email}"
        else
          failure_count += 1
          Rails.logger.warn "[DailyReminderJob] ❌ Failed to send reminder to #{user.email}"
        end

        # Send daily in-app notification
        NotificationService.create_app_reminder_notification(user)

        # Small delay to prevent overwhelming email server
        sleep(0.1) if Rails.env.production?

      rescue => e
        failure_count += 1
        Rails.logger.error "[DailyReminderJob] Error processing user #{user.id}: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
      end
    end

    total_time = Time.current - start_time

    Rails.logger.info "[DailyReminderJob] ===== DAILY REMINDERS COMPLETE ====="
    Rails.logger.info "[DailyReminderJob] Total time: #{total_time.round(2)} seconds"
    Rails.logger.info "[DailyReminderJob] Success: #{success_count}, Failures: #{failure_count}"

    # Log summary to monitoring
    log_daily_summary(success_count, failure_count, total_time)
  end

  private

  def log_daily_summary(success_count, failure_count, total_time)
    # This could be sent to monitoring services like:
    # - Sentry
    # - Rollbar
    # - Custom monitoring dashboard
    # - Slack notifications for failures

    if failure_count > 0
      Rails.logger.warn "[DailyReminderJob] ⚠️  #{failure_count} users failed to receive daily reminders"
    end

    if success_count > 0
      Rails.logger.info "[DailyReminderJob] 📧 Successfully sent #{success_count} daily reminder emails"
    end
  end
end
