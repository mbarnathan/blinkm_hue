#!/usr/bin/ruby

require 'json'
require 'colorize'
load 'hue.rb'

def read_script(filename)
  hex2dec = lambda { |x| x.to_i(16) }
  script = '"data": [ ' + IO.read(filename) + ' ]'
  script = script.reverse.sub(',', '').reverse
  script = script.gsub(/0x(\h{2})/, &hex2dec)
  script = script.gsub(/\/\/.*$/, '')
  script = script.gsub("'", '"')
  script = script.gsub("{", "[").gsub("}", "]")
  script = "{ #{script} }"
  return JSON.parse(script)
end

if ARGV.length != 2
  abort("Usage: #{$0} lightscript bulb_number")
end

$lightscript = ARGV[0]
$script_json = read_script($lightscript)

$shutdown = false

$bulb = Hue::Bulb.new(ARGV[1])
puts "Initial settings: #{$bulb.rgb}".light_white
$bulb.stash!
$bulb.on
$on = true

Signal.trap("INT") {
  puts "Interrupt received, beginning graceful shutdown!".light_red
  $shutdown = true
}

Signal.trap("TERM") {
  puts "SIGTERM received, beginning graceful shutdown!".light_red
  $shutdown = true
}

Signal.trap("HUP") {
  puts "SIGHUP received, re-reading #{$lightscript}".light_white
  $script_json = read_script($lightscript)
}

def cRand(base, upper, variance)
  if variance == 0 then return base end
  newBase = base + rand(variance) - variance / 2
  return [[0, newBase].max, upper].min
end

def execute(command)
  if $shutdown then return end

  b = $bulb
  (delay, data) = command
  instruction = data[0]
  params = data.drop(1)

  ticks_per_second = 30.0
  case instruction
    when 'f'
      b.transition_time = (255 - params[0]) / (ticks_per_second * 10.0)
    when 't'
      new_adjust = params[0]
      $time_adjust = (new_adjust == 0) ? 0 : ($time_adjust + new_adjust)
    when 'h'
      if params[2] == 0 then
        if $on then
          b.off
          $on = false
        end
      else
        if ! $on then
          b.on
          $on = true
        end
        b.update hue:params[0] * 65535 / 255, sat:params[1], bri: params[2]
      end
    when 'H'
      b.update hue:cRand(b.hue, 65535, params[0] * 65535 / 255), sat:cRand(b.sat, 255, params[1]), bri:cRand(b.brightness, 255, params[2])
    when 'c'
      if params[0] == 0 and params[1] == 0 and params[2] == 0 then
        if $on then
          b.off
          $on = false
        end
      else
        if ! $on then
          b.on
          $on = true
        end
        b.rgb = params
      end
    when 'C'
      b.rgb = [cRand(b.red, 255, params[0]), cRand(b.green, 255, params[1]), cRand(b.blue, 255, params[2])]
  end
  sleep_time = (delay + $time_adjust) / ticks_per_second
  sleep sleep_time
end

while ! $shutdown do
  $time_adjust = 0
  $script_json["data"].each { |cmd|
      $secs = 1
      begin
            execute(cmd)
      rescue SocketError => e
            STDERR.puts "Error connecting: #{$e}. Will retry in #{$secs} seconds."
            STDERR.flush
            sleep $secs
            $bulb = Hue::Bulb.new(3)
            $secs = [$secs * 2, 30].min
            retry
      end
  }
end

$bulb.restore!

puts "Old bulb settings restored.".light_white

