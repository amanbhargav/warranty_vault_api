# frozen_string_literal: true

# Service responsible for scheduling warranty reminder jobs
# Handles all scheduling logic including edge cases
class WarrantyReminderService
  # Number of days before expiry to send reminder
  REMINDER_DAYS_BEFORE = 30

  attr_reader :warranty

  def initialize(warranty)
    @warranty = warranty
  end

  # Schedule a reminder job for this warranty
  # Returns true if scheduled, false if not needed
  def schedule_reminder
    return false unless should_schedule?

    if reminder_date <= Time.current
      # Reminder date is in the past, send immediately
      send_immediate_reminder
    else
      # Schedule for future execution
      schedule_future_reminder
    end

    true
  end

  # Cancel a previously scheduled reminder job
  # Used when warranty is updated or deleted
  def cancel_reminder
    # Sidekiq doesn't have built-in job cancellation
    # We rely on the reminder_sent flag to prevent execution
    Rails.logger.info "[WarrantyReminderService] Cancelling reminder for warranty #{warranty.id}"
  end

  # Reschedule a reminder (e.g., if warranty dates changed)
  def reschedule_reminder
    # Reset the reminder_sent flag to allow re-scheduling
    warranty.update!(reminder_sent: false, last_reminder_sent_at: nil)
    schedule_reminder
  end

  class << self
    # Schedule reminders for all warranties on an invoice
    def schedule_for_invoice(invoice)
      return unless invoice.persisted?

      invoice.product_warranties.find_each do |warranty|
        new(warranty).schedule_reminder
      end

      Rails.logger.info "[WarrantyReminderService] Scheduled reminders for invoice #{invoice.id}"
    end

    # Find and process all warranties needing reminders
    # Called by the daily scheduler job
    def process_due_reminders
      due_warranties = ProductWarranty.due_for_reminder

      Rails.logger.info "[WarrantyReminderService] Found #{due_warranties.count} warranties due for reminder"

      due_warranties.find_each do |warranty|
        WarrantyReminderJob.perform_later(warranty.id)
      end

      due_warranties.count
    end

    # Process recently expired warranties (post-expiry notification)
    def process_recently_expired
      recently_expired = ProductWarranty.where(
        expires_at: 7.days.ago.to_date..Date.current,
        reminder_sent: false
      )

      Rails.logger.info "[WarrantyReminderService] Found #{recently_expired.count} recently expired warranties"

      recently_expired.find_each do |warranty|
        WarrantyReminderJob.perform_later(warranty.id)
      end

      recently_expired.count
    end
  end

  private

  # Determine if we should schedule a reminder
  def should_schedule?
    return false unless warranty.persisted?
    return false unless warranty.expires_at
    return false if warranty.reminder_sent

    true
  end

  # Calculate when to send the reminder
  def reminder_date
    @reminder_date ||= warranty.expires_at - REMINDER_DAYS_BEFORE.days
  end

  # Send reminder immediately (warranty is already close to expiry)
  def send_immediate_reminder
    Rails.logger.info "[WarrantyReminderService] Sending immediate reminder for warranty #{warranty.id}"
    WarrantyReminderJob.perform_later(warranty.id)
  end

  # Schedule reminder for future execution
  def schedule_future_reminder
    Rails.logger.info "[WarrantyReminderService] Scheduling reminder for warranty #{warranty.id} at #{reminder_date}"

    WarrantyReminderJob
      .set(wait_until: reminder_date.beginning_of_day)
      .perform_later(warranty.id)
  end
end
