{
  "targets": [
    {
      "target_name": "pathwatcher",
      "sources": [
        "src/main.cc",
        "src/common.cc",
        "src/common.h",
      ],
      "include_dirs": [
        "src"
      ],
      "conditions": [
        ['OS=="win"', {
          "sources": [
            "src/pathwatcher_win.cc",
          ],
        }],  # OS=="win"
        ['OS=="mac"', {
          "sources": [
            "src/pathwatcher_mac.mm",
          ],
        }],  # OS=="mac"
      ],
    }
  ]
}
