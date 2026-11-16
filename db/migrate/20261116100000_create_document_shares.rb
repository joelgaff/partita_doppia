class CreateDocumentShares < ActiveRecord::Migration[8.1]
  def change
    create_table :document_shares do |t|
      t.references :document, null: false, foreign_key: true, index: { unique: true }   # one link per document
      t.references :organization, null: false, foreign_key: true
      t.string :token, null: false   # encrypted; the index is on the ciphertext
      t.datetime :created_at, null: false
      t.index :token, unique: true
    end
  end
end
