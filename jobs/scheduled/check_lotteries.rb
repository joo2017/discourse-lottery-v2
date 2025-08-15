module Jobs
  class CheckLotteries < ::Jobs::Scheduled
    every 1.minute

    def execute(args)
      # 查询所有状态为 'running' 的抽奖
      running_lotteries = Lottery.running

      # 只有在确实有正在进行的抽奖时，才进行下一步的迭代处理
      # 这样可以避免在没有抽奖时进行不必要的数据库查询
      return if running_lotteries.empty?

      running_lotteries.find_each do |lottery|
        begin
          # 检查抽奖条件是否满足
          should_draw = if lottery.by_time? && lottery.draw_at
                          Time.zone.now >= lottery.draw_at
                        elsif lottery.by_reply? && lottery.draw_reply_count
                          # 使用 topic.posts_count 即可，Discourse 内部会高效处理
                          # 减 1 是为了排除楼主的帖子
                          lottery.topic.posts_count - 1 >= lottery.draw_reply_count
                        else
                          false
                        end
          
          # 如果条件满足，则执行开奖
          if should_draw
            LotteryManager.new(lottery).perform_draw
          end

        # 捕获并记录在处理单个抽奖时可能发生的任何异常
        # 这样可以防止一个抽奖的失败影响到其他抽奖的检查
        rescue => e
          Rails.logger.error("LOTTERY_DRAW_ERROR: Failed to process lottery ##{lottery.id} for topic ##{lottery.topic_id}. Error: #{e.class.name}: #{e.message}\n#{e.backtrace.join("\n")}")
        end
      end
    end
  end
end
