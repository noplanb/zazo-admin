require 'rails_helper'

RSpec.describe Message, type: :model do
  let(:s3_event_raw) { json_fixture('s3_event')['Records'] }
  let(:s3_event) { Event.create_from_s3_event(s3_event_raw).first }
  let(:file_name) { s3_event.video_filename }
  let(:sender_id) { s3_event.sender_id }
  let(:receiver_id) { s3_event.receiver_id }
  let(:message) { described_class.new(file_name) }
  let(:instance) { message }
  let(:missing_events) { Message::ALL_EVENTS - [%w(video s3 uploaded)] }
  let(:data) { s3_event.data }
  let(:data_ios_android) do
    data.merge 'sender_platform' => 'ios',
               'receiver_platform' => 'android'
  end

  describe '#initialize' do
    context 'by file_name' do
      let(:options) { {} }
      let(:instance) { described_class.new(file_name, options) }

      context '#file_name' do
        subject { instance.file_name }
        it { is_expected.to eq(file_name) }

        context 'with events parameter' do
          let(:events) do
            result = [s3_event]
            result += receive_video(data)
            result += download_video(data)
            result += view_video(data)
            result
          end
          let(:options) { { events: events } }

          context '#events' do
            subject { instance.events }
            it { is_expected.to eq(events) }
          end
        end

        context 'with event_names parameter' do
          let(:event_names) { Message::ALL_EVENTS }
          let(:options) { { event_names: event_names } }

          context '#event_names' do
            subject { instance.event_names }
            it { is_expected.to eq(event_names) }
          end
        end
      end

      context '#s3_event' do
        subject { instance.s3_event }
        it { is_expected.to eq(s3_event) }
      end
    end

    context 'by s3 event' do
      let(:instance) { described_class.new(s3_event) }

      context '#file_name' do
        subject { instance.file_name }
        it { is_expected.to eq(file_name) }
      end

      context '#s3_event' do
        subject { instance.s3_event }
        it { is_expected.to eq(s3_event) }
      end
    end

    context 'by not s3 event' do
      subject { described_class.new(build(:event, :video_kvstore_received)) }

      specify do
        expect { subject }.to raise_error(TypeError, 'value must be either file_name or video:s3:uploaded (video:sent) event')
      end
    end
  end

  context '#events' do
    subject { instance.events }

    context 'only when S3 uploaded' do
      it { is_expected.to eq([s3_event]) }
    end

    context 'all' do
      let(:events) do
        result = [s3_event]
        result += receive_video(data)
        result += download_video(data)
        result += view_video(data)
        result
      end
      it { is_expected.to eq(events) }
    end

    context 'with events given in initializer' do
      let(:instance) { described_class.new(file_name, events: []) }

      specify do
        expect(Event).to_not receive(:with_video_filename).with(file_name)
        subject
      end
    end
  end

  context '#s3_event' do
    subject { instance.s3_event }
    it { is_expected.to eq(s3_event) }

    context 'no s3 event found' do
      let(:file_name) { 'unknown' }
      specify do
        expect { subject }.to raise_error('no video:s3:uploaded (video:sent) event found')
      end
    end
  end

  context '#data' do
    subject { instance.data }
    specify do
      is_expected.to eq(
        'sender_id' => sender_id,
        'receiver_id' => receiver_id,
        'video_filename' => file_name)
    end
  end

  context '#raw_params' do
    subject { instance.raw_params }
    it { is_expected.to eq(Hashie::Mash.new(s3_event.raw_params)) }
  end

  context '#id' do
    subject { instance.id }
    it { is_expected.to eq(file_name) }
  end

  context '#file_name' do
    subject { instance.file_name }
    it { is_expected.to eq(file_name) }
  end

  context '#uploaded_at' do
    subject { instance.uploaded_at }
    it { is_expected.to eq(s3_event.triggered_at) }
  end

  context '#file_size' do
    subject { instance.file_size }
    it { is_expected.to eq(94_555) }
  end

  context '#sender_platform' do
    subject { instance.sender_platform }
    context 'with platforms' do
      before do
        receive_video data_ios_android
        download_video data_ios_android
        view_video data_ios_android
      end
      it { is_expected.to eq(:ios) }
    end
    context 'without platforms' do
      before do
        receive_video data
        download_video data
        view_video data
      end
      it { is_expected.to eq(:unknown) }
    end
  end

  context '#receiver_platform' do
    subject { instance.receiver_platform }
    context 'with platforms' do
      before do
        receive_video data_ios_android
        download_video data_ios_android
        view_video data_ios_android
      end
      it { is_expected.to eq(:android) }
    end
    context 'without platforms' do
      before do
        receive_video data
        download_video data
        view_video data
      end
      it { is_expected.to eq(:unknown) }
    end
  end

  context 'to_hash' do
    subject { instance.to_hash }
    specify do
      expected = {
        id: file_name,
        sender_id: sender_id,
        receiver_id: receiver_id,
        uploaded_at: '2015-04-22T18:01:20.663Z'.to_datetime,
        file_name: file_name,
        file_size: 94_555,
        missing_events: missing_events,
        status: 'uploaded',
        delivered: false,
        viewed: false,
        complete: false
      }
      is_expected.to eq expected
    end
  end

  context 'to_json' do
    subject { instance.to_json }
    specify do
      is_expected.to eq(instance.to_hash.to_json)
    end
  end

  describe '#status' do
    subject { instance.status }

    context 'uploaded' do
      before do
        instance
      end

      it { is_expected.to eq('uploaded') }
    end

    context 'received' do
      before do
        receive_video data
      end

      it { is_expected.to eq('received') }
    end

    context 'downloaded' do
      before do
        receive_video data
        download_video data
      end

      it { is_expected.to eq('downloaded') }
    end

    context 'viewed' do
      before do
        receive_video data
        download_video data
        view_video data
      end

      it { is_expected.to eq('viewed') }

      describe '.viewed?' do
        subject { instance.status.viewed? }
        it { is_expected.to be true }
      end
    end
  end

  describe '#delivered?' do
    subject { instance.delivered? }

    context 'uploaded' do
      it { is_expected.to be false }
    end

    context 'received' do
      before do
        receive_video data
      end

      it { is_expected.to be false }
    end

    context 'downloaded' do
      before do
        receive_video data
        download_video data
      end

      it { is_expected.to be true }
    end

    context 'viewed' do
      before do
        receive_video data
        download_video data
        view_video data
      end

      it { is_expected.to be true }
    end
  end

  describe '#undelivered?' do
    subject { instance.undelivered? }

    context 'uploaded' do
      it { is_expected.to be true }
    end

    context 'received' do
      before do
        receive_video data
      end

      it { is_expected.to be true }
    end

    context 'downloaded' do
      before do
        receive_video data
        download_video data
      end

      it { is_expected.to be false }
    end

    context 'viewed' do
      before do
        receive_video data
        download_video data
        view_video data
      end

      it { is_expected.to be false }
    end
  end

  describe '.all' do
    let(:video_1) { video_data(sender_id, receiver_id, gen_video_id) }
    let(:video_2) { video_data(gen_hash, receiver_id, gen_video_id) }
    let(:video_3) { video_data(sender_id, gen_hash, gen_video_id) }
    let(:video_4) { video_data(sender_id, gen_hash, gen_video_id) }
    let(:video_5) { video_data(sender_id, gen_hash, gen_video_id) }
    let!(:message_1) { described_class.new(video_1[:video_filename]) }
    let!(:message_2) { described_class.new(video_2[:video_filename]) }
    let!(:message_3) { described_class.new(video_3[:video_filename]) }
    let!(:message_4) { described_class.new(video_3[:video_filename]) }
    let!(:message_5) { described_class.new(video_3[:video_filename]) }
    let(:options) { {} }
    let(:list) { described_class.all(options) }
    let(:instance) { list.first }
    subject { list }

    before do
      send_video data # check for duplications
      send_video video_1
      send_video video_2
      send_video video_3
    end

    it { is_expected.to eq([message, message_1, message_2, message_3]) }

    context 'first' do
      subject { instance }

      context '#events' do
        subject { instance.events }

        it { is_expected.to all(be_an(Event)) }

        specify do
          expect(Event).to_not receive(:with_video_filename).with(file_name)
          subject
        end

        it 'all with specified video_filename' do
          is_expected.to all(satisfy { |e| e.video_filename == file_name })
        end
      end
    end

    context 'reverse' do
      let(:options) { { reverse: true } }
      it { is_expected.to eq([message_3, message_2, message_1, message]) }
    end

    context 'when sender_id given' do
      let(:options) { { sender_id: sender_id } }
      it { is_expected.to eq([message, message_1, message_3]) }
    end

    context 'when receiver_id given' do
      let(:options) { { receiver_id: receiver_id } }
      it { is_expected.to eq([message, message_1, message_2]) }
    end

    context 'with time frame' do
      let(:options) { { start_date: 2.day.ago.to_date, end_date: Date.today } }
      before do
        Timecop.travel(3.days.ago) do
          send_video video_4
          send_video video_5
        end
      end
      it { is_expected.to eq([message, message_1, message_2, message_3]) }
    end
  end

  describe '#missing_events' do
    subject { instance.missing_events }

    context 'kvstore: R, D; notification: V' do
      before do
        notification_receive_video data
        notification_download_video data
        kvstore_view_video data
      end

      it do
        is_expected.to eq([
          %w(video kvstore received),
          %w(video kvstore downloaded),
          %w(video notification viewed)
        ]) end
    end

    context 'notification: D, V' do
      before do
        receive_video data
        kvstore_download_video data
        kvstore_view_video data
      end

      it do
        is_expected.to eq([
          %w(video notification downloaded),
          %w(video notification viewed)
        ]) end
    end

    context 'kvstore: V' do
      before do
        receive_video data
        download_video data
        notification_view_video data
      end

      it do
        is_expected.to eq([
          %w(video kvstore viewed)
        ])
      end
    end
  end

  describe '#event_names' do
    subject { instance.event_names }

    context 'U, N:R, N:D, K:V' do
      before do
        notification_receive_video data
        notification_download_video data
        kvstore_view_video data
      end

      it do
        is_expected.to eq([
          %w(video s3 uploaded),
          %w(video notification received),
          %w(video notification downloaded),
          %w(video kvstore viewed)
        ]) end
    end

    context 'R, K:D, K:V' do
      before do
        receive_video data
        kvstore_download_video data
        kvstore_view_video data
      end

      it do
        is_expected.to eq([
          %w(video s3 uploaded),
          %w(video kvstore received),
          %w(video notification received),
          %w(video kvstore downloaded),
          %w(video kvstore viewed)
        ]) end
    end

    context 'R, D, N:V' do
      before do
        receive_video data
        download_video data
        notification_view_video data
      end

      it do
        is_expected.to eq([
          %w(video s3 uploaded),
          %w(video kvstore received),
          %w(video notification received),
          %w(video kvstore downloaded),
          %w(video notification downloaded),
          %w(video notification viewed)])
      end
    end
  end

  describe '#complete?' do
    subject { instance.complete? }

    context 'empty' do
      before do
        video_flow data
      end

      it { is_expected.to be true }
    end

    context 'kvstore: R, D; notification: V' do
      before do
        notification_receive_video data
        notification_download_video data
        kvstore_view_video data
      end

      it { is_expected.to be false }
    end
  end

  describe '#incomplete?' do
    subject { instance.incomplete? }

    context 'empty' do
      before do
        video_flow data
      end

      it { is_expected.to be false }
    end

    context 'kvstore: R, D; notification: V' do
      before do
        notification_receive_video data
        notification_download_video data
        kvstore_view_video data
      end

      it { is_expected.to be true }
    end
  end

  describe '#viewed?' do
    subject { instance.viewed? }

    context 'full flow' do
      before do
        video_flow data
      end

      it { is_expected.to be true }
    end

    context 'without K:V' do
      before do
        receive_video data
        download_video data
        notification_view_video data
      end

      it { is_expected.to be true }
    end

    context 'without N:V' do
      before do
        receive_video data
        download_video data
        kvstore_view_video data
      end

      it { is_expected.to be true }
    end

    context 'without KN:V' do
      before do
        receive_video data
        download_video data
      end

      it { is_expected.to be false }
    end
  end

  describe '#unviewed?' do
    subject { instance.unviewed? }

    context 'full flow' do
      before do
        video_flow data
      end

      it { is_expected.to be false }
    end

    context 'without K:V' do
      before do
        receive_video data
        download_video data
        notification_view_video data
      end

      it { is_expected.to be false }
    end

    context 'without N:V' do
      before do
        receive_video data
        download_video data
        kvstore_view_video data
      end

      it { is_expected.to be false }
    end

    context 'without KN:V' do
      before do
        receive_video data
        download_video data
      end

      it { is_expected.to be true }
    end
  end

  describe '.build_from_events_scope' do
    let(:scope) { Event.all }
    let(:list) { described_class.build_from_events_scope(scope).sort_by(&:uploaded_at) }
    let(:video_1) { video_data(sender_id, receiver_id, gen_video_id).merge(
      'sender_platform' => 'ios',
      'receiver_platform' => 'android') }
    let(:video_2) { video_data(gen_hash, receiver_id, gen_video_id).merge(
      'sender_platform' => 'ios',
      'receiver_platform' => 'ios') }
    let(:video_3) { video_data(sender_id, gen_hash, gen_video_id).merge(
      'sender_platform' => 'android',
      'receiver_platform' => 'android') }
    let(:message_1) { described_class.new(video_1[:video_filename]) }
    let(:message_2) { described_class.new(video_2[:video_filename]) }
    let(:message_3) { described_class.new(video_3[:video_filename]) }
    let(:instance) { list.first }
    subject { list }

    before do
      Timecop.scale(3600) do
        video_flow data_ios_android # check for duplications
        video_flow video_1
        video_flow video_2
        video_flow video_3
      end
    end

    it { is_expected.to eq([message, message_1, message_2, message_3]) }

    context 'instance' do
      context 'sender_platform' do
        subject { instance.sender_platform }
        it 'should not load events' do
          expect_any_instance_of(Message).to_not receive(:find_platform)
          subject
        end

        it { is_expected.to eq(:ios) }
      end
      context 'receiver_platform' do
        subject { instance.receiver_platform }
        it 'should not load events' do
          expect_any_instance_of(Message).to_not receive(:find_platform)
          subject
        end

        it { is_expected.to eq(:android) }
      end
    end
  end
end
