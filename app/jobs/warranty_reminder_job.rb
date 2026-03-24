# frozen_string_literal: true

# Background job to send warranty expiration reminders
# Scheduled to run 30 days before warranty expiry
#
# Usage:
#   WarrantyReminderJob.perform_later(warranty_id)
#   WarrantyReminderJob.set(wait_until: date).perform_later(warranty_id)
class WarrantyReminderJob < ApplicationJob
  queue_as :default

  # Retry configuration
  retry_on ActiveRecord::RecordNotFound, wait: :exponentially_longer, attempts: 3
  discard_on ActiveJob::DeserializationError

  # Sidekiq unique jobs requires sidekiq-unique-jobs gem
  # For now, we rely on the reminder_sent flag for idempotency

  def perform(warranty_id)
    warranty = find_warranty(warranty_id)
    return unless warranty

    # Idempotency check - skip if already sent
    if warranty.reminder_sent
      Rails.logger.info "[WarrantyReminderJob] Skipping warranty #{warranty_id} - reminder already sent"
      return
    end

    Rails.logger.info "[WarrantyReminderJob] Processing reminder for warranty #{warranty_id}"

    user = warranty.invoice.user
    return unless user&.email_verified?

    # Create in-app notification
    NotificationService.create_warranty_expiry_notification(user, [ warranty ])

    # Broadcast real-time update
    WarrantyBroadcastService.broadcast_warranty_expiry_alert(warranty)

    # Send email notification
    if EmailService.send_warranty_notification(user, [ warranty ])
      warranty.update!(reminder_sent: true)
      Rails.logger.info "[WarrantyReminderJob] Reminder sent for warranty #{warranty_id}"
    else
      Rails.logger.error "[WarrantyReminderJob] Failed to send reminder for warranty #{warranty_id}"
    end
  rescue => e
    Rails.logger.error "[WarrantyReminderJob] Error processing warranty #{warranty_id}: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    raise
  end

  private

  # Find warranty with proper error handling
  def find_warranty(warranty_id)
    ProductWarranty.find_by(id: warranty_id)
  rescue => e
    Rails.logger.error "[WarrantyReminderJob] Error finding warranty #{warranty_id}: #{e.message}"
    nil
  end
end
