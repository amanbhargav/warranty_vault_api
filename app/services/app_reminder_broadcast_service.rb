# frozen_string_literal: true

# Service for broadcasting app reminders via ActionCable
class AppReminderBroadcastService
  class << self
    # Broadcast app reminder to user's WebSocket channel
    def broadcast_app_reminder(user)
      return unless ActionCable.server.present?

      channel_name = "user_#{user.id}"
      
      data = {
        type: 'app_reminder',
        title: 'Warranty Vault Reminder',
        message: 'We are here to safely store your important invoices and track your product warranties.',
        action_url: '/dashboard',
        timestamp: Time.current.iso8601
      }

      ActionCable.server.broadcast(channel_name, data)
      
      Rails.logger.info "[AppReminderBroadcastService] Broadcasted app reminder to user #{user.id}"
    rescue => e
      Rails.logger.error "[AppReminderBroadcastService] Failed to broadcast app reminder to user #{user.id}: #{e.message}"
    end
  end
end
