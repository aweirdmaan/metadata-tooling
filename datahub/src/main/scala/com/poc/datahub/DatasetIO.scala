package com.poc.datahub

import org.apache.spark.sql.{Dataset, Encoder, SparkSession}
import org.apache.spark.sql.functions.col

object DatasetIO {

  def readCsv[T: Encoder](path: String)(implicit spark: SparkSession): Dataset[T] = {
    val schema = implicitly[Encoder[T]].schema
    spark.read
      .option("header", "true")
      .option("inferSchema", "false")
      .csv(path)
      .select(schema.fields.map(f => col(f.name).cast(f.dataType).as(f.name)): _*)
      .as[T]
  }

  def writeParquet[T: Encoder](ds: Dataset[T], path: String): Unit =
    ds.write.mode("overwrite").parquet(path)
}
