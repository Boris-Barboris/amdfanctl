import core.stdc.signal;
import core.stdc.stdio: FILE, fopen, fclose, fwrite, puts;
import core.stdc.stdlib: exit;

import core.thread: Thread;
import core.time: seconds;

import std.algorithm: min, max;
import std.conv: to;
import std.stdio: writeln, File;
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
    int stopFanTemp = 55000;
    int fullFanTemp = 95000;
    ubyte fanStopPower = 83;
    ubyte fanStartPower = 90;
    int period = 3;

    bool manualModeWasSet;
}

int main()
{
    scope(exit) setMode(FanMode.automatic);
    signal(SIGINT, &handleSignal);
    signal(SIGTERM, &handleSignal);
    ubyte prevDesiredPower = 0;
    while(true)
    {
        int currentTemp = getCurrentTemperature();
        float tempRatio = (currentTemp - stopFanTemp) / float(fullFanTemp - stopFanTemp);
        ubyte desiredPower = max(0.0f, min(255.0f, fanStartPower + tempRatio * (255.0f - fanStartPower))).to!ubyte;
        // hysteresis
        if (desiredPower <= fanStopPower || (prevDesiredPower <= fanStopPower && desiredPower <= fanStartPower))
            desiredPower = 0;
        desiredPower = max(fanStartPower, desiredPower);
        prevDesiredPower = desiredPower;
        writeln("temp = ", currentTemp, ", desiredPower = ", desiredPower);
        setMode(FanMode.manual);
        setFanPower(desiredPower);
        Thread.sleep(seconds(period));
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
    File powerFile = File(powerFileName, "w");
    powerFile.writeln(power.to!string);
}

FanMode getFanMode()
{
    File modeFile = File(fanmodeFileName, "r");
    return modeFile.readln().stripRight.to!FanMode;
}

int getCurrentTemperature()
{
    File temperFile = File(temperatureFileName, "r");
    return temperFile.readln().stripRight.to!int;
}

extern(C) void handleSignal(int sig) nothrow @nogc
{
    if (manualModeWasSet)
    {
        setMode(FanMode.automatic);
        exit(0);
    }
}
