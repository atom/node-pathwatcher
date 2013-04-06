{
  "targets": [
    {
      "target_name": "pathwatcher",
      "sources": [
        "main.cc",
        "common.cc",
        "common.h",
        "pathwatcher_mac.mm"
      ],
      'link_settings': {
        'libraries': [
          '$(SDKROOT)/System/Library/Frameworks/AppKit.framework',
        ],
      },
    }
  ]
}

