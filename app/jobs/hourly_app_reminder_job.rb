# frozen_string_literal: true

# Hourly background job to send app reminders to users
# Runs every hour to remind users about the app and warranty tracking
#
# Usage:
#   HourlyAppReminderJob.perform_later
#   HourlyAppReminderJob.set(wait_until: 1.hour.from_now).perform_later
class HourlyAppReminderJob < ApplicationJob
  queue_as :default

  # Rate limiting: only send once per user per day
  REMINDER_INTERVAL = 24.hours

  def perform
    Rails.logger.info "[HourlyAppReminderJob] Starting hourly app reminder process"

    # Find users who haven't received a reminder in the last 24 hours
    users_to_remind = find_users_needing_reminders

    Rails.logger.info "[HourlyAppReminderJob] Found #{users_to_remind.count} users to remind"

    users_to_remind.find_each do |user|
      send_app_reminder(user)
    end

    Rails.logger.info "[HourlyAppReminderJob] Completed hourly app reminder process"
  end

  private

  # Find users who need reminders (haven't received one in the last 24 hours)
  def find_users_needing_reminders
    User.where(
      'last_app_reminder_sent_at IS NULL OR last_app_reminder_sent_at < ?',
      REMINDER_INTERVAL.ago
    ).where(email_verified: true)
  end

  # Send app reminder to user
  def send_app_reminder(user)
    return unless user.email_verified?

    # Create in-app notification
    NotificationService.create_app_reminder_notification(user)

    # Broadcast real-time update
    AppReminderBroadcastService.broadcast_app_reminder(user)

    # Send email notification
    if EmailService.send_app_reminder(user)
      user.update!(last_app_reminder_sent_at: Time.current)
      Rails.logger.info "[HourlyAppReminderJob] Sent app reminder to user #{user.id}"
    else
      Rails.logger.error "[HourlyAppReminderJob] Failed to send app reminder to user #{user.id}"
    end
  rescue => e
    Rails.logger.error "[HourlyAppReminderJob] Error sending reminder to user #{user.id}: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
  end
end
