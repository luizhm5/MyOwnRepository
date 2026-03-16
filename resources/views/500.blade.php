@extends('content')

@section('body')
    @if(session()->has('msg'))
        {{ session('msg') }}
    @else
        An error has occurred. Please contact the system administrator.
    @endif
@endsection
