import core.stdc.errno;
import core.stdc.signal;
import core.stdc.stdio;
import core.stdc.stdlib: exit;

import core.thread: Thread;
import core.time: seconds;

import std.algorithm: min, max;
import std.conv: to;
import std.exception: ErrnoException;
import std.stdio: writeln;
import std.string: toStringz, stripRight;


enum FanMode: int
{
    manual = 1,
    automatic = 2
}

__gshared
{
    string fanmodeFileName = "/sys/class/drm/card0/device/hwmon/hwmon2/pwm1_enable\0";
    string powerFileName = "/sys/class/drm/card0/device/hwmon/hwmon2/pwm1\0";
    string temperatureFileName = "/sys/class/drm/card0/device/hwmon/hwmon2/temp1_input\0";
    int stopFanTemp = 50000;
    int fullFanTemp = 85000;
    ubyte fanStopPower = 80;
    ubyte fanStartPower = 90;

    bool manualModeWasSet;
}

int main()
{
    scope(exit) setMode(FanMode.automatic);
    signal(SIGINT, &handleSignal);
    signal(SIGTERM, &handleSignal);
    setMode(FanMode.manual);
    while(true)
    {
        int currentTemp = getCurrentTemperature();
        float tempRatio = (currentTemp - stopFanTemp) / float(fullFanTemp - stopFanTemp);
        ubyte desiredPower = max(0.0f, min(255.0f, fanStartPower + tempRatio * (255.0f - fanStartPower))).to!ubyte;
        if (desiredPower <= fanStopPower)
            desiredPower = 0;
        writeln("temp = ", currentTemp, ", desiredPower = ", desiredPower);
        setFanPower(desiredPower);
        Thread.sleep(seconds(2));
    }
}

void setMode(FanMode mode) nothrow @nogc
{
    FILE* modeFile = fopen(fanmodeFileName.ptr, "w\0".ptr);
    if (modeFile is null)
    {
        puts("Unable to open modeFile\0".ptr);
        return;
    }
    scope(exit) fclose(modeFile);
    string autoModeString;
    final switch (mode)
    {
        case FanMode.manual:
            autoModeString = "1\n";
            manualModeWasSet = true;
            break;
        case FanMode.automatic:
            autoModeString = "2\n";
            break;
    }
    fwrite(autoModeString.ptr, 1, 2, modeFile);
}

void setFanPower(ubyte power)
{
    FILE* powerFile = fopen(powerFileName.ptr, "w\0".ptr);
    if (powerFile is null)
        throw new ErrnoException("Unable to open powerFile", errno());
    scope(exit) fclose(powerFile);
    string powerString = power.to!string ~ "\n";
    fwrite(powerString.ptr, 1, powerString.length, powerFile);
}

FanMode getFanMode()
{
    FILE* modeFile = fopen(fanmodeFileName.ptr, "r\0".ptr);
    if (modeFile is null)
        throw new ErrnoException("Unable to open modeFile", errno());
    scope(exit) fclose(modeFile);
    char[] result;
    result.length = 2;
    fread(result.ptr, 1, 2, modeFile);
    return result.stripRight.to!FanMode;
}

int getCurrentTemperature()
{
    FILE* temperFile = fopen(temperatureFileName.ptr, "r\0".ptr);
    if (temperFile is null)
        throw new ErrnoException("Unable to open temperFile", errno());
    scope(exit) fclose(temperFile);
    char[] result;
    result.length = 16;
    size_t charsRead = fread(result.ptr, 1, 16, temperFile);
    return result[0..charsRead].stripRight.to!int;
}

extern(C) void handleSignal(int sig) nothrow @nogc
{
    if (manualModeWasSet)
    {
        setMode(FanMode.automatic);
        exit(0);
    }
}
