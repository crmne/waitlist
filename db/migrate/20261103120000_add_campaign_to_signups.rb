class AddCampaignToSignups < ActiveRecord::Migration[8.1]
  def change
    add_column :signups, :campaign, :string
    add_column :signups, :campaign_content, :string
  end
end
