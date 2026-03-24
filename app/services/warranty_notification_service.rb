# frozen_string_literal: true

# Service responsible for creating and managing warranty notifications
# Handles both in-app notifications and email notifications
class WarrantyNotificationService
  attr_reader :warranty, :invoice, :user

  def initialize(warranty)
    @warranty = warranty
    @invoice = warranty.invoice
    @user = invoice.user
  end

  # Create all notifications for a warranty reminder
  def send_reminder
    Rails.logger.info "[WarrantyNotificationService] Sending reminder for warranty #{warranty.id}"

    in_app_result = create_in_app_notification
    email_result = queue_email_notification

    {
      success: true,
      in_app: in_app_result,
      email: email_result
    }
  end

  # Create in-app notification
  def create_in_app_notification
    days_remaining = warranty.days_remaining || 0

    Notification.create!(
      user: user,
      title: build_title(days_remaining),
      message: build_message(days_remaining),
      notification_type: :warranty_expiring,
      action_url: "/invoices/#{invoice.id}",
      read: false,
      metadata: {
        warranty_id: warranty.id,
        invoice_id: invoice.id,
        component_name: warranty.component_name,
        days_remaining: days_remaining,
        expires_at: warranty.expires_at&.iso8601
      }
    )

    Rails.logger.info "[WarrantyNotificationService] In-app notification created for user #{user.id}"
    true
  rescue => e
    Rails.logger.error "[WarrantyNotificationService] Failed to create in-app notification: #{e.message}"
    false
  end

  # Queue email for delivery
  def queue_email_notification
    days_remaining = warranty.days_remaining || 0

    WarrantyMailer.with(
      user: user,
      invoice: invoice,
      warranty: warranty,
      days_remaining: days_remaining
    ).warranty_expiring_soon.deliver_later

    Rails.logger.info "[WarrantyNotificationService] Email queued for user #{user.email}"
    true
  rescue => e
    Rails.logger.error "[WarrantyNotificationService] Failed to queue email: #{e.message}"
    false
  end

  # Create expired warranty notification (post-expiry)
  def send_expired_notification
    Notification.create!(
      user: user,
      title: "Warranty Expired",
      message: build_expired_message,
      notification_type: :warranty_expired,
      action_url: "/invoices/#{invoice.id}",
      read: false,
      metadata: {
        warranty_id: warranty.id,
        invoice_id: invoice.id,
        expired_at: warranty.expires_at&.iso8601
      }
    )

    WarrantyMailer.with(
      user: user,
      invoice: invoice,
      warranty: warranty,
      days_remaining: 0
    ).warranty_expired.deliver_later

    Rails.logger.info "[WarrantyNotificationService] Expired notification sent for warranty #{warranty.id}"
  end

  # Create upload success notification with warranty info
  def send_upload_notification
    Notification.create!(
      user: user,
      title: "Warranty Added",
      message: "#{warranty.component_display_name} warranty for #{invoice.product_name} has been added. " \
               "We'll remind you #{WarrantyReminderService::REMINDER_DAYS_BEFORE} days before it expires.",
      notification_type: :upload_successful,
      action_url: "/invoices/#{invoice.id}",
      read: false,
      metadata: {
        warranty_id: warranty.id,
        invoice_id: invoice.id,
        expires_at: warranty.expires_at&.iso8601
      }
    )

    Rails.logger.info "[WarrantyNotificationService] Upload notification sent for warranty #{warranty.id}"
  end

  class << self
    # Create reminder notification for a warranty
    def send_reminder_for(warranty)
      new(warranty).send_reminder
    end

    # Create expired notification for a warranty
    def send_expired_for(warranty)
      new(warranty).send_expired_notification
    end

    # Create upload notification for a warranty
    def send_upload_for(warranty)
      new(warranty).send_upload_notification
    end

    # Bulk send reminders for multiple warranties
    def send_bulk_reminders(warranties)
      results = { success: 0, failed: 0 }

      warranties.find_each do |warranty|
        begin
          send_reminder_for(warranty)
          results[:success] += 1
        rescue => e
          Rails.logger.error "[WarrantyNotificationService] Bulk reminder failed: #{e.message}"
          results[:failed] += 1
        end
      end

      results
    end
  end

  private

  def build_title(days_remaining)
    if days_remaining <= 0
      "⚠️ Warranty Expired"
    elsif days_remaining <= 7
      "⚠️ Urgent: Warranty Expiring"
    elsif days_remaining <= 14
      "Reminder: Warranty Expiring Soon"
    else
      "Warranty Expiry Reminder"
    end
  end

  def build_message(days_remaining)
    component = warranty.component_display_name
    product_name = invoice.product_name || "Your product"
    expiry_date = warranty.expires_at.strftime("%d %b %Y")

    case
    when days_remaining <= 0
      "Your #{product_name} #{component} warranty has expired (#{expiry_date})."
    when days_remaining <= 7
      "Your #{product_name} #{component} warranty will expire in #{days_remaining} days (#{expiry_date})."
    when days_remaining <= 30
      "Your #{product_name} #{component} warranty will expire on #{expiry_date}."
    else
      "Your #{product_name} #{component} warranty will expire in approximately #{(days_remaining / 30.0).ceil} months."
    end
  end

  def build_expired_message
    component = warranty.component_display_name
    product_name = invoice.product_name || "Your product"
    expiry_date = warranty.expires_at.strftime("%d %b %Y")

    "Your #{product_name} #{component} warranty expired on #{expiry_date}. " \
    "Consider checking for replacement options or extended warranty plans."
  end
end
