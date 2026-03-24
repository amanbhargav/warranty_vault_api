# Scheduled job to check for warranties needing reminders
# Runs daily to find warranties expiring in the next 30 days
class WarrantySchedulerJob < ApplicationJob
  queue_as :default

  # Run daily at 9 AM
  # Use a cron-like scheduler or Sidekiq-Cron to schedule this job
  def perform
    Rails.logger.info "[WarrantySchedulerJob] Starting daily warranty reminder check"

    # Find all warranties expiring in the next 30 days that haven't had reminders sent
    expiring_warranties = ProductWarranty.due_for_reminder

    Rails.logger.info "[WarrantySchedulerJob] Found #{expiring_warranties.count} warranties needing reminders"

    # Queue individual reminder jobs
    expiring_warranties.each do |warranty|
      WarrantyReminderJob.perform_later(warranty.id)
    end

    # Also check for warranties that expired recently (within last 7 days) for post-expiry notifications
    recently_expired = ProductWarranty.where(
      expires_at: 7.days.ago..Date.current,
      reminder_sent: true
    ).where.not(last_reminder_sent_at: 7.days.ago..Date.current)

    Rails.logger.info "[WarrantySchedulerJob] Found #{recently_expired.count} recently expired warranties for post-expiry notifications"

    recently_expired.each do |warranty|
      WarrantyReminderJob.perform_later(warranty.id)
    end

    Rails.logger.info "[WarrantySchedulerJob] Warranty reminder check completed"
  end
end
