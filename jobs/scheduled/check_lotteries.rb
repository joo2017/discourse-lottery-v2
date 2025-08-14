module Jobs
  class CheckLotteries < ::Jobs::Scheduled
    every 1.minute

    def execute(args)
      # --- START: 最终的逻辑修复 ---
      # 查询所有“进行中”的抽奖
      Lottery.where(status: Lottery::STATUSES[:running]).find_each do |lottery|
        begin
          topic = lottery.topic
          next unless topic # 如果主题被删除，则跳过

          should_draw = false
          
          # 使用我们新定义的、更明确的方法进行比较
          if lottery.is_draw_by_time? && lottery.draw_at && Time.now >= lottery.draw_at
            should_draw = true
          elsif lottery.is_draw_by_reply? && lottery.draw_reply_count && (topic.posts_count - 1) >= lottery.draw_reply_count
            should_draw = true
          end

          if should_draw
            Rails.logger.warn "LOTTERY_DRAW_DEBUG: Conditions met for lottery ##{lottery.id}. Performing draw."
            LotteryManager.new(lottery).perform_draw
          end
        rescue => e
          Rails.logger.error "LOTTERY_DRAW_ERROR: Failed to check lottery ##{lottery.id}. Error: #{e.message}"
        end
      end
      # --- END: 最终的逻辑修复 ---
    end
  end
end
