module Jobs
  class CheckLotteries < ::Jobs::Scheduled
    every 1.minute

    def execute(args)
      Rails.logger.warn("LOTTERY_DEBUG: [CheckLotteries Job] Starting check...")
      
      running_lotteries = Lottery.where(status: Lottery::STATUSES[:running])
      
      Rails.logger.warn("LOTTERY_DEBUG: [CheckLotteries Job] Found #{running_lotteries.count} running lotteries.")

      running_lotteries.find_each do |lottery|
        begin
          topic = lottery.topic
          unless topic
            Rails.logger.warn("LOTTERY_DEBUG: [CheckLotteries Job] Skipping lottery ##{lottery.id} because its topic has been deleted.")
            next
          end

          Rails.logger.warn("LOTTERY_DEBUG: [CheckLotteries Job] Checking lottery ##{lottery.id} for topic ##{topic.id} ('#{topic.title}').")

          should_draw = false
          
          if lottery.draw_type == Lottery::DRAW_TYPES[:by_time]
            draw_at = lottery.draw_at
            current_time = Time.zone.now
            Rails.logger.warn("LOTTERY_DEBUG: -> Type: by_time. Draw at: #{draw_at}, Current time: #{current_time}")
            if draw_at && current_time >= draw_at
              should_draw = true
            end
          elsif lottery.draw_type == Lottery::DRAW_TYPES[:by_reply]
            current_replies = topic.posts_count - 1
            target_replies = lottery.draw_reply_count
            Rails.logger.warn("LOTTERY_DEBUG: -> Type: by_reply. Target replies: #{target_replies}, Current replies: #{current_replies}")
            if target_replies && current_replies >= target_replies
              should_draw = true
            end
          end

          if should_draw
            Rails.logger.warn("LOTTERY_DEBUG: -> Conditions MET. Performing draw for lottery ##{lottery.id}.")
            LotteryManager.new(lottery).perform_draw
          else
            Rails.logger.warn("LOTTERY_DEBUG: -> Conditions NOT met. Skipping draw for lottery ##{lottery.id}.")
          end
        rescue => e
          Rails.logger.error("LOTTERY_DRAW_ERROR: Failed to check lottery ##{lottery.id}. Error: #{e.class.name} - #{e.message}\n#{e.backtrace.join("\n")}")
        end
      end
      Rails.logger.warn("LOTTERY_DEBUG: [CheckLotteries Job] Check finished.")
    end
  end
end
