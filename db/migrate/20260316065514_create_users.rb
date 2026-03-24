class CreateUsers < ActiveRecord::Migration[8.0]
  def change
    create_table :users do |t|
      t.string :email
      t.string :password_digest
      t.string :first_name
      t.string :last_name
      t.string :google_uid
      t.string :avatar_url
      t.integer :role
      t.datetime :last_sign_in_at
      t.integer :sign_in_count

      t.timestamps
    end
    add_index :users, :email, unique: true
    add_index :users, :google_uid, unique: true
  end
end
