@extends('content')

@section('body')
    @if($task->state == -1)
        <h3>Error, please contact your system administrator</h3>
        <code>{{ $task->error_msg }}</code>
    @elseif($task->progress < 100)
        <h3>Processing, please wait <div class="lds-ellipsis"><div></div><div></div><div></div><div></div></div></h3>
        <div class="progress">
            <progress max="100" value="0"></progress>
            <div class="progress-value">{{ $task->progress }}%</div>
            <div class="progress-bg"><div class="progress-bar"></div></div>
        </div>
    @else
        @if($task->isFinal)
            <h3>Process finished. File uploaded to Google Drive.</h3>
        @else
            <h3>Process finished, <a href="{{ $task->file_url }}" target="_blank">download file</a></h3>
        @endif
    @endif

    <div class="log">
        <textarea id="log_input">{{ $task->log }}</textarea>
    </div>
@endsection

@section('script')
    @if(isset($canvasClient))
        /*window.Sfdc.canvas.client.autogrow({!! json_encode($canvasClient) !!}, true, 100)*/
    @endif

    @if($task->progress < 100 && $task->state != -1)
        setInterval(function() {
        window.location.reload(true);
        }, 3000);
    @endif

    let textarea = document.getElementById('log_input');
    textarea.scrollTop = textarea.scrollHeight;
@endsection

@section('intohead')
    @if($canvasClient)
        <!--<script src="libs/canvas-all.js"></script>-->
    @endif

    <style type="text/css">

        .progress {
            font: 12px Arial, Tahoma, sans-serif;
            position: relative;
            overflow: hidden;
        }

        .progress progress {
            position: absolute;
            width: 0;
            height: 0;
            overflow: hidden;
            left: -777px;
        }

        .progress-bar {
            overflow: hidden;
            background: #099AD6;
            width: {{ $task->progress }}%;
            height: 100%;
            position: absolute;
            top: 0;
            left: 0;
        }

        .progress-value {
            color: #333;
            display: block;
            line-height: 21px;
            text-align: center;
        }

        .progress-bg {
            background: #e6e9ed;
            position: relative;
            height: 8px;
            border-radius: 5px;
            overflow: hidden;
        }

        .log{
            margin-top: 10px;
        }
        .log textarea{
            width: 100%;
            height: 40vh;
            font-family: 'Roboto', sans-serif;
        }

        .lds-ellipsis {
            display: inline-block;
            position: relative;
            width: 64px;
            height: 38px;
        }
        .lds-ellipsis div {
            position: absolute;
            top: 27px;
            width: 11px;
            height: 11px;
            border-radius: 50%;
            background: #69BAD4;
            animation-timing-function: cubic-bezier(0, 1, 1, 0);
        }
        .lds-ellipsis div:nth-child(1) {
            left: 6px;
            animation: lds-ellipsis1 0.6s infinite;
        }
        .lds-ellipsis div:nth-child(2) {
            left: 6px;
            animation: lds-ellipsis2 0.6s infinite;
        }
        .lds-ellipsis div:nth-child(3) {
            left: 26px;
            animation: lds-ellipsis2 0.6s infinite;
        }
        .lds-ellipsis div:nth-child(4) {
            left: 45px;
            animation: lds-ellipsis3 0.6s infinite;
        }
        @keyframes lds-ellipsis1 {
            0% {
                transform: scale(0);
            }
            100% {
                transform: scale(1);
            }
        }
        @keyframes lds-ellipsis3 {
            0% {
                transform: scale(1);
            }
            100% {
                transform: scale(0);
            }
        }
        @keyframes lds-ellipsis2 {
            0% {
                transform: translate(0, 0);
            }
            100% {
                transform: translate(19px, 0);
            }
        }

    </style>
@endsection
