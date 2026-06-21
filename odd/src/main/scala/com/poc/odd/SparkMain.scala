package com.poc.odd

import org.apache.spark.sql.SparkSession
import scopt.OParser

trait SparkMain[C] {
  def appName: String
  def defaultArgs: C
  def argParser: OParser[Unit, C]
  def run(args: C)(implicit spark: SparkSession): Unit

  protected def sparkBuilder(): SparkSession.Builder =
    SparkSession.builder().appName(appName).master("local[*]")

  def main(args: Array[String]): Unit =
    OParser.parse(argParser, args, defaultArgs).foreach { cfg =>
      implicit val spark: SparkSession = sparkBuilder().getOrCreate()
      run(cfg)
      spark.stop()
    }
}
