# frozen_string_literal: true

# Service for broadcasting real-time warranty updates via ActionCable
class WarrantyBroadcastService
  class << self
    # Broadcast warranty creation
    def broadcast_warranty_created(warranty)
      return unless warranty && defined?(ActionCable)

      user = warranty.invoice.user
      
      ActionCable.server.broadcast(
        "user_#{user.id}_warranties",
        {
          type: 'warranty_created',
          warranty: serialize_warranty(warranty),
          timestamp: Time.current.iso8601
        }
      )

      Rails.logger.info "[WarrantyBroadcastService] Broadcasted warranty creation for user #{user.id}"
    rescue => e
      Rails.logger.error "[WarrantyBroadcastService] Failed to broadcast warranty creation: #{e.message}"
    end

    # Broadcast warranty status update
    def broadcast_warranty_status_update(warranty, old_status, new_status)
      return unless warranty && defined?(ActionCable)

      user = warranty.invoice.user
      
      ActionCable.server.broadcast(
        "user_#{user.id}_warranties",
        {
          type: 'warranty_status_update',
          warranty_id: warranty.id,
          old_status: old_status,
          new_status: new_status,
          warranty: serialize_warranty(warranty),
          timestamp: Time.current.iso8601
        }
      )

      Rails.logger.info "[WarrantyBroadcastService] Broadcasted warranty status update for user #{user.id}"
    rescue => e
      Rails.logger.error "[WarrantyBroadcastService] Failed to broadcast warranty status update: #{e.message}"
    end

    # Broadcast warranty expiry alert
    def broadcast_warranty_expiry_alert(warranty)
      return unless warranty && defined?(ActionCable)

      user = warranty.invoice.user
      days_remaining = warranty.days_remaining || 0
      
      ActionCable.server.broadcast(
        "user_#{user.id}_warranties",
        {
          type: 'warranty_expiry_alert',
          warranty: serialize_warranty(warranty),
          days_remaining: days_remaining,
          urgency: calculate_urgency(days_remaining),
          timestamp: Time.current.iso8601
        }
      )

      Rails.logger.info "[WarrantyBroadcastService] Broadcasted warranty expiry alert for user #{user.id}"
    rescue => e
      Rails.logger.error "[WarrantyBroadcastService] Failed to broadcast warranty expiry alert: #{e.message}"
    end

    # Broadcast warranty deletion
    def broadcast_warranty_deleted(warranty_id, user_id)
      return unless warranty_id && user_id && defined?(ActionCable)

      ActionCable.server.broadcast(
        "user_#{user_id}_warranties",
        {
          type: 'warranty_deleted',
          warranty_id: warranty_id,
          timestamp: Time.current.iso8601
        }
      )

      Rails.logger.info "[WarrantyBroadcastService] Broadcasted warranty deletion for user #{user_id}"
    rescue => e
      Rails.logger.error "[WarrantyBroadcastService] Failed to broadcast warranty deletion: #{e.message}"
    end

    # Broadcast bulk warranty updates
    def broadcast_bulk_warranty_updates(user, warranties)
      return unless user && warranties.any? && defined?(ActionCable)

      ActionCable.server.broadcast(
        "user_#{user.id}_warranties",
        {
          type: 'bulk_warranty_update',
          warranties: warranties.map { |w| serialize_warranty(w) },
          count: warranties.count,
          timestamp: Time.current.iso8601
        }
      )

      Rails.logger.info "[WarrantyBroadcastService] Broadcasted bulk warranty update for user #{user.id}"
    rescue => e
      Rails.logger.error "[WarrantyBroadcastService] Failed to broadcast bulk warranty update: #{e.message}"
    end

    private

    # Serialize warranty for broadcasting
    def serialize_warranty(warranty)
      {
        id: warranty.id,
        invoice_id: warranty.invoice_id,
        component: warranty.component_display_name,
        warranty_status: warranty.warranty_status,
        expires_at: warranty.expires_at,
        days_remaining: warranty.days_remaining,
        created_at: warranty.created_at,
        updated_at: warranty.updated_at
      }
    end

    # Calculate urgency based on days remaining
    def calculate_urgency(days_remaining)
      case days_remaining
      when 0..7
        'critical'
      when 8..30
        'warning'
      when 31..90
        'info'
      else
        'low'
      end
    end
  end
end
