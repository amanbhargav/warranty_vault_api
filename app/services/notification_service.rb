# frozen_string_literal: true

# Service for handling in-app notifications
class NotificationService
  NOTIFICATION_TYPES = %w[info warning success error warranty_expiring warranty_expired invoice_processed system_update].freeze

  class << self
    # Create a new notification
    def create_notification(user, title, message, options = {})
      return nil unless user

      notification = user.notifications.create!(
        title: title,
        message: message,
        notification_type: options[:type] || "info",
        action_url: options[:action_url],
        metadata: options[:metadata] || {}
      )

      Rails.logger.info "[NotificationService] Created notification for user #{user.id}: #{title}"

      # Broadcast real-time update if ActionCable is available
      broadcast_notification(notification) if should_broadcast?(options)

      notification
    end

    # Create warranty expiry notification
    def create_warranty_expiry_notification(user, warranties)
      return nil if warranties.empty?

      warranty_count = warranties.length
      title = "Warranty Expiring Soon"
      message = "#{warranty_count} product#{warranty_count > 1 ? 's' : ''} expiring in the next 30 days"

      notification = create_notification(
        user,
        title,
        message,
        type: "warranty_expiring",
        action_url: "/dashboard",
        metadata: {
          warranty_ids: warranties.map(&:id),
          expiry_dates: warranties.map { |w| [ w.id, w.expires_at ] }.to_h
        }
      )

      # Send email notification
      EmailService.send_warranty_notification(user, warranties)

      notification
    end

    # Create invoice processed notification
    def create_invoice_processed_notification(user, invoice)
      return nil unless user && invoice

      title = "Invoice Processed"
      message = "Your invoice for #{invoice.product_name || 'uploaded file'} has been processed"

      create_notification(
        user,
        title,
        message,
        type: "invoice_processed",
        action_url: "/invoice/#{invoice.id}",
        metadata: {
          invoice_id: invoice.id,
          product_name: invoice.product_name
        }
      )
    end

    # Create system update notification
    def create_system_notification(title, message, options = {})
      User.find_each do |user|
        create_notification(
          user,
          title,
          message,
          type: "system_update",
          metadata: options[:metadata] || {}
        )
      end
    end

    # Create login notification
    def create_login_notification(user)
      create_notification(
        user,
        "Login Successful",
        "Welcome back! We are here to keep your expensive product invoices and track warranties.",
        type: "success",
        action_url: "/dashboard"
      )
    end

    # Create product added notification
    def create_product_added_notification(user, product_or_invoice)
      return nil unless user && product_or_invoice

      # Handle both Product and Invoice objects
      product_name = if product_or_invoice.respond_to?(:name)
                       product_or_invoice.name
      elsif product_or_invoice.respond_to?(:product_name)
                       product_or_invoice.product_name
      else
                       "New product"
      end

      create_notification(
        user,
        "Product Added Successfully",
        "#{product_name} has been added to your warranty vault.",
        type: "success",
        action_url: if product_or_invoice.respond_to?(:id)
                      "/invoices/#{product_or_invoice.id}"
                    else
                      "/dashboard"
                    end,
        metadata: {
          product_id: product_or_invoice.respond_to?(:id) ? product_or_invoice.id : nil,
          product_name: product_name,
          brand: product_or_invoice.respond_to?(:brand) ? product_or_invoice.brand : nil
        }
      )
    end

    # Create app reminder notification
    def create_app_reminder_notification(user)
      return nil unless user

      title = "Warranty Vault Reminder"
      message = "We are here to keep your expensive product invoice and track warranty"

      create_notification(
        user,
        title,
        message,
        type: "info",
        action_url: "/dashboard",
        metadata: {
          reminder_type: "app_reminder",
          sent_at: Time.current
        }
      )
    end

    # Mark notification as read
    def mark_as_read(notification_id, user)
      notification = user.notifications.find_by(id: notification_id)
      return { success: false, error: "Notification not found" } unless notification

      notification.update!(read: true)

      Rails.logger.info "[NotificationService] Marked notification #{notification_id} as read for user #{user.id}"

      { success: true, notification: notification }
    end

    # Mark all notifications as read for user
    def mark_all_as_read(user)
      count = user.notifications.where(read: false).update_all(read: true)

      Rails.logger.info "[NotificationService] Marked #{count} notifications as read for user #{user.id}"

      { success: true, count: count }
    end

    # Get unread count for user
    def unread_count(user)
      user.notifications.where(read: false).count
    end

    # Get notifications for user with pagination
    def get_notifications(user, options = {})
      page = options[:page] || 1
      per_page = options[:per_page] || 20
      unread_only = options[:unread_only] || false
      type = options[:type]

      notifications = user.notifications.includes(:user)
      notifications = notifications.where(read: false) if unread_only
      notifications = notifications.where(notification_type: type) if type

      total_count = notifications.count
      total_pages = (total_count.to_f / per_page.to_i).ceil

      paginated_notifications = notifications.order(created_at: :desc)
                                             .offset((page.to_i - 1) * per_page.to_i)
                                             .limit(per_page.to_i)

      {
        notifications: paginated_notifications,
        unread_count: unread_count(user),
        pagination: {
          current_page: page.to_i,
          total_pages: total_pages,
          total_count: total_count,
          per_page: per_page.to_i
        }
      }
    end

    # Delete notification
    def delete_notification(notification_id, user)
      notification = user.notifications.find_by(id: notification_id)
      return { success: false, error: "Notification not found" } unless notification

      notification.destroy!

      Rails.logger.info "[NotificationService] Deleted notification #{notification_id} for user #{user.id}"

      { success: true }
    end

    # Clean up old notifications (older than 30 days)
    def cleanup_old_notifications(days = 30)
      cutoff_date = days.days.ago
      count = Notification.where("created_at < ?", cutoff_date).delete_all

      Rails.logger.info "[NotificationService] Cleaned up #{count} old notifications"
      count
    end

    private

    # Determine if notification should be broadcasted via WebSocket
    def should_broadcast?(options)
      # Don't broadcast for bulk notifications
      return false if options[:broadcast] == false

      # Always broadcast for individual user notifications
      true
    end

    # Broadcast notification via ActionCable
    def broadcast_notification(notification)
      return unless defined?(ActionCable)

      begin
        ActionCable.server.broadcast(
          "user_#{notification.user_id}_notifications",
          {
            type: "new_notification",
            notification: notification.serialize,
            unread_count: unread_count(notification.user),
            timestamp: Time.current.iso8601
          }
        )

        Rails.logger.info "[NotificationService] Broadcasted notification for user #{notification.user_id}"
      rescue => e
        Rails.logger.error "[NotificationService] Failed to broadcast notification: #{e.message}"
        # Don't raise error - notification still created successfully
      end
    end
  end
end
