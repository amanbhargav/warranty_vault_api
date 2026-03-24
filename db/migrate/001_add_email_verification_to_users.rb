# frozen_string_literal: true

class AddEmailVerificationToUsers < ActiveRecord::Migration[7.0]
  def change
    add_column :users, :email_verified, :boolean, default: false, null: false
    add_column :users, :verification_token, :string
    add_column :users, :verification_sent_at, :datetime
    add_column :users, :email_verified_at, :datetime

    # Add indexes for performance
    add_index :users, :verification_token, unique: true
    add_index :users, :email_verified
    add_index :users, :verification_sent_at
  end
end
