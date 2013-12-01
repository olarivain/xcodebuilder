# xcodebuilder, a gem for managing iOS builds

xcodebuilder is a fork from [BetaBuilder](https://github.com/lukeredpath/betabuilder), heavily modified to be more generic and convenient.
It was written to simplify CI for iOS and OSX project, as a mere ruby wrapper on xcodebuild.

In a nutshell, it supports:
* Building iOS and OSX apps
* Uploading iOS apps to testflightapp.com.
* Git tagging builds
* Automatically incrementing the `kCFBundleVersionKey` key for your project
* Linting and releasing a CocoaPod library

All this is implemented in plain ruby, and distributed as a ruby gem, which makes it quite trivial to integrate that with `rake`, or do more complex things should you want to.

In short, xcodebuilder is the best thing since chocolate milkshake to setup your Cocoa CI tracks: it takes care of scripting xcodebuild, taking all this complexity away from you, while you still retain fine grain control over your build.
You can pick your signing identity, add random extra params, upload your builds to TF (with or without DSYM).
If your project is simple and you don't require any of this fanciness, your rakefile is about 15 lines short.
If your project is complex and you require a bunch of fanciness, your rakefile is about 30 lines short. w00t!x


## Usage

The simplest is to integrate xcodebuilder within a Rakefile.
Start off by installing xcodebuilder:

    $ sudo gem install xcodebuilder

Include the xcodebuilder gem by adding the following at the top of your Rakefile:
    require 'rubygems'
    require 'xcodebuilder'

Instantiate a builder object:

    builder = XcodeBuilder::XcodeBuilder.new do |config|
        config.app_name = "YOUR_APP_NAME"
      end

Build your project. This will package an IPA and drop it in ./pkg:

    task :build do
      builder.package
    end

Release your project. This will package the IPA, drop it in ./pkg, increment the build number and git tag the tree:

    task :build do
      builder.release
    end

## Configuration
A full list of configuration options and their details

More coming!

## License

This code is licensed under the MIT license.

Copyright (c) 2010 Luke Redpath
Copyright (c) 2013 Olivier Larivain

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
