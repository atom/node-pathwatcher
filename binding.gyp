{
  "targets": [
    {
      "target_name": "pathwatcher",
      "sources": [
        "src/main.cc",
        "src/common.cc",
        "src/common.h",
        "src/handle_map.cc",
        "src/handle_map.h",
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
