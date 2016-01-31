class MessagesController < ApplicationController
  def index
    @messages = Message.all messages_params
    @sender   = User.find_by_mkey(messages_params[:sender_id])
    @receiver = User.find_by_mkey(messages_params[:receiver_id])
    @filter = params[:filter]
    @messages.select!(&:"#{@filter}?") if @filter && Message.new.respond_to?(:"#{@filter}?")
    @messages = MessageDecorator.decorate_collection(@messages)
  end

  def show
    @message = Message.new(params[:id]).decorate
  end

  def duplications
    @metric = Metric.new name: 'upload_duplications_data', type: 'upload_duplications_data'
  end

  private

  def messages_params
    params.permit(:sender_id, :receiver_id, :reverse, :page, :per, :filter)
  end
end
