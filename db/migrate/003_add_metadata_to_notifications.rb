# frozen_string_literal: true

class AddMetadataToNotifications < ActiveRecord::Migration[8.0]
  def change
    # Add metadata column if it doesn't exist
    add_column :notifications, :metadata, :json unless column_exists?(:notifications, :metadata)
    
    # Change message column to text if it's not already
    change_column :notifications, :message, :text unless column_exists?(:notifications, :message)
    
    # Add default values for notification_type if needed
    change_column_default :notifications, :notification_type, 'info' unless column_exists?(:notifications, :notification_type)
    change_column_null :notifications, :notification_type, false
    
    # Update null values before adding not null constraints
    execute "UPDATE notifications SET read = false WHERE read IS NULL" if column_exists?(:notifications, :read)
    execute "UPDATE notifications SET title = 'Untitled' WHERE title IS NULL" if column_exists?(:notifications, :title)
    execute "UPDATE notifications SET message = 'No message' WHERE message IS NULL" if column_exists?(:notifications, :message)
    
    change_column_null :notifications, :read, false
    change_column_null :notifications, :title, false
    change_column_null :notifications, :message, false
  end
end
