# name: discourse-lottery-v2
# about: A modern, automated lottery plugin for Discourse.
# version: 2.2.6
# authors: Your Name (Designed by AI)
# url: null

enabled_site_setting :lottery_v2_enabled

register_asset "stylesheets/common/lottery.scss"

after_initialize do
  require_dependency File.expand_path('../app/models/lottery.rb', __FILE__)
  
  Topic.class_eval do
    has_one :lottery, class_name: "Lottery", dependent: :destroy
  end

  [
    '../app/services/lottery_creator.rb',
    '../app/services/lottery_manager.rb',
    '../jobs/scheduled/check_lotteries.rb',
    '../jobs/regular/create_lottery_from_topic.rb',
    '../app/controllers/admin/lottery_admin_controller.rb'
  ].each { |path| require_dependency File.expand_path(path, __FILE__) }
  
  Discourse::Application.routes.append do
    get '/admin/plugins/lottery-v2' => 'admin/lottery_admin#index', constraints: StaffConstraint.new
    put '/admin/plugins/lottery-v2/settings' => 'admin/lottery_admin#update_settings', constraints: StaffConstraint.new
  end

  on(:topic_created) do |topic, opts, user|
    if SiteSetting.lottery_v2_enabled
      Rails.logger.warn "LOTTERY_DEBUG: Topic created event triggered for topic ID #{topic.id} in category #{topic.category_id} with tags [#{topic.tags.map(&:name).join(', ')}]."
      
      trigger_categories = SiteSetting.lottery_v2_trigger_categories.split('|').map(&:to_i).compact
      trigger_tags = SiteSetting.lottery_v2_trigger_tags.split('|').map(&:downcase).compact_blank

      category_match = trigger_categories.empty? || trigger_categories.include?(topic.category_id)
      tags_match = trigger_tags.empty? || !((topic.tags.map(&:name).map(&:downcase) & trigger_tags).empty?)
      
      Rails.logger.warn "LOTTERY_DEBUG: Checking conditions for topic ##{topic.id}. Category match: #{category_match} (Required: #{trigger_categories.inspect}), Tags match: #{tags_match} (Required: #{trigger_tags.inspect})"

      if category_match && tags_match
        Rails.logger.warn "LOTTERY_DEBUG: Conditions met. Enqueuing job for topic ID #{topic.id}"
        Jobs.enqueue(:create_lottery_from_topic, topic_id: topic.id)
      else
        Rails.logger.warn "LOTTERY_DEBUG: Conditions NOT met. Job not enqueued."
      end
    else
      Rails.logger.warn "LOTTERY_DEBUG: Topic created, but plugin is disabled (lottery_v2_enabled = false)."
    end
  end

  require_dependency "topic_view_serializer"
  class ::TopicViewSerializer
    attributes :lottery_data

    def lottery_data
      lottery = object.topic.lottery
      return nil unless lottery

      lottery.as_json(
        only: [
          :name, :prize, :winner_count, :draw_type, :draw_at,
          :draw_reply_count, :specific_floors, :description,
          :extra_info, :status, :winner_data
        ],
        methods: [:participating_user_count]
      ).merge(
        status: lottery.status_name.to_s,
        draw_type: lottery.draw_type_name.to_s
      )
    end
    
    def include_lottery_data?
      object.topic.lottery.present?
    end
  end
end
