#include "TimeUtil.hpp"
#include <cassert>
#include <cstdio>

int main()
{
    using namespace vt;
    assert(formatTime(0) == "0:00.00");
    assert(formatTime(83.456) == "1:23.46");
    assert(formatTime(3723.5) == "1:02:03.50");
    assert(formatTime(5, true) == "0:00:05.00");
    assert(formatTime(-3) == "0:00.00");
    assert(formatTimeForFilename(83.4) == "01m23s");
    assert(formatTimeForFilename(3723) == "1h02m03s");

    assert(parseTime("83").value() == 83.0);
    assert(parseTime("1:23").value() == 83.0);
    assert(parseTime("1:23.5").value() == 83.5);
    assert(parseTime("1:23,5").value() == 83.5);
    assert(parseTime(" 1 : 02 : 03 ").value() == 3723.0);
    assert(parseTime("90:00").value() == 5400.0);
    assert(!parseTime("").has_value());
    assert(!parseTime("abc").has_value());
    assert(!parseTime("1:2:3:4").has_value());
    assert(!parseTime("1.5:00").has_value());
    assert(!parseTime(":").has_value());
    assert(!parseTime(".").has_value());

    // Rundreise
    for (double t : {0.0, 0.5, 59.99, 61.0, 3600.0, 7325.25}) {
        auto back = parseTime(formatTime(t));
        assert(back.has_value());
        assert(std::fabs(*back - t) < 0.006);
    }
    std::puts("TimeUtil: alle Tests OK");
    return 0;
}
